// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

part 'image_batch_service.prepare.dart';
part 'image_batch_service.review.dart';
part 'image_batch_service.store.dart';

class ImageBatchService extends ChangeNotifier {
  ImageBatchService(this.storage, this.image) {
    storage.rootRelocation.blockers.add(_rootBlocker);
    storage.addListener(_rootListener);
    ready = _load();
  }
  late final VoidCallback _rootListener = _rootChanged;
  late final String? Function() _rootBlocker = _rootMoveBlocker;
  final StorageService storage;
  final ImageGenService image;
  late final Future<void> ready;
  String? _storedRoot;
  bool _loaded = false;
  int _pendingWrites = 0;
  final List<ImageBatchJob> _jobs = [];
  List<ImageBatchJob> get jobs => List.unmodifiable(_jobs);
  bool running = false;
  bool working = false;
  bool pauseRequested = false;
  String? error;
  Future<void> _writes = Future.value();
  @override
  void dispose() {
    storage.removeListener(_rootListener);
    storage.rootRelocation.blockers.remove(_rootBlocker);
    super.dispose();
  }

  void _changed() => notifyListeners();
  void reportError(Object problem) {
    error = '$problem';
    _changed();
  }

  Map<String, dynamic> snapshot() {
    final s = storage.imageGenSettings;
    final prefs = s.prefs;
    final keys = (prefs?.getKeys() ?? <String>{}).where((key) {
      final plain = key.startsWith('beta_') ? key.substring(5) : key;
      return plain.startsWith('image_') ||
          plain.startsWith('comfy_') ||
          plain.startsWith('draw_things') ||
          plain == 'local_image_gen_url';
    }).toList()..sort();
    return {
      'root': storage.rootPath,
      'backend': s.imageGenBackend,
      'model': s.imageGenModel,
      'editModel': s.imageGenEditModel,
      'size': s.imageGenSize,
      'negativePrompt': s.imageGenNegativePrompt,
      'createGraph': s.comfyCreateWorkflowId,
      'editGraph': s.comfyEditWorkflowId,
      'fingerprint': sha256
          .convert(
            utf8.encode(
              jsonEncode({
                for (final key in keys) key: prefs!.get(key),
                if (s.imageGenBackend == 'remote')
                  'resolvedRemoteUrl': s.imageRemoteApiUrl.trim().isEmpty
                      ? storage.backendSettings.remoteApiUrl
                      : s.imageRemoteApiUrl,
              }),
            ),
          )
          .toString(),
    };
  }

  Map<String, dynamic> view() => {
    'running': running,
    'working': working,
    'pauseRequested': pauseRequested,
    'error': error,
    'jobs': [for (final job in _jobs) job.view()],
  };

  void pause() {
    pauseRequested = true;
    notifyListeners();
  }

  Future<void> run() async {
    await ready;
    _requireRootStable();
    if (running || working || image.isGenerating) {
      throw StateError('Another image operation is busy.');
    }
    if (expressionPackBoard.run != null) {
      throw StateError('Finish or discard the current expression pack first.');
    }
    running = true;
    pauseRequested = false;
    error = null;
    notifyListeners();
    try {
      final started = await image.startExpressionPack([], (_) async {
        for (final job in _jobs.where((j) => j.state == 'waiting').toList()) {
          if (pauseRequested) break;
          if (job.state != 'waiting') continue;
          if (jsonEncode(job.data['config']) != jsonEncode(snapshot())) {
            error =
                'Image settings changed. Restore the captured configuration or prepare another pass.';
            break;
          }
          job.data['state'] = 'running';
          try {
            await _persist();
            final source = job.data['source'] as String?;
            final bytes = await image.expressionFrame(
              prompt: job.prompt,
              negativePrompt: job.data['negativePrompt'] as String,
              size: job.data['size'] as String,
              referenceImage: source == null
                  ? null
                  : await _file(source).readAsBytes(),
              seed: job.data['seed'] as int,
              denoise: (job.data['denoise'] as num).toDouble(),
              intent: job.edit ? StudioIntent.edit : StudioIntent.create,
              editStrength: job.edit
                  ? (job.data['denoise'] as num).toDouble()
                  : null,
            );
            if (bytes == null) {
              throw StateError(
                image.statusMessage.isEmpty
                    ? 'Generation returned no image.'
                    : image.statusMessage,
              );
            }
            final normalized = await imageBatchPixels(bytes);
            if (normalized == null) {
              throw StateError('Generation returned an unreadable image.');
            }
            final name = '${job.id}.png';
            await _file(name).writeAsBytes(normalized, flush: true);
            job.data.addAll({
              'state': 'review',
              'candidate': name,
              'error': null,
            });
          } catch (e) {
            job.data.addAll({'state': 'failed', 'error': '$e'});
            error =
                'Generation stopped. Review the failed request before continuing.';
            pauseRequested = true;
          }
          await _persist();
        }
        return <String>[];
      });
      if (started == null) {
        throw StateError('Another generation acquired the image service.');
      }
    } finally {
      running = false;
      notifyListeners();
    }
  }
}
