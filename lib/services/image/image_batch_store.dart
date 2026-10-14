// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/image.dart';

class ImageBatchStore {
  ImageBatchStore(this.storage, this.image, this.onChanged) {
    storage.rootRelocation.blockers.add(_blocker);
    storage.addListener(_listener);
    ready = reload();
  }
  final StorageService storage;
  final ImageGenService image;
  final VoidCallback onChanged;
  final List<ImageBatchJob> jobs = [];
  CharacterRepository? repository;
  late final VoidCallback _listener = rootChanged;
  late final String? Function() _blocker = rootMoveBlocker;
  late Future<void> ready;
  String? storedRoot;
  bool loaded = false;
  bool loadFailed = false;
  bool closed = false;
  int pendingWrites = 0;
  bool running = false;
  bool working = false;
  bool pauseRequested = false;
  String? error;
  Future<void> writes = Future.value();
  void changed() {
    if (!closed) onChanged();
  }

  void dispose() {
    closed = true;
    pauseRequested = true;
    storage.removeListener(_listener);
    storage.rootRelocation.blockers.remove(_blocker);
  }

  Future<void> reload() async {
    try {
      await load();
      loadFailed = false;
      error = null;
    } catch (problem) {
      loadFailed = true;
      error = 'Could not load image batches: $problem';
    }
    changed();
  }

  Map<String, dynamic> snapshot() {
    final s = storage.imageGenSettings;
    final prefs = s.prefs;
    final keys = (prefs?.getKeys() ?? <String>{}).where((key) {
      final plain = key.startsWith('beta_') ? key.substring(5) : key;
      return RegExp(
            r'^image_gen_(backend|model|edit_model|steps|cfg_scale|sampler|scheduler|loras|lora|lora_weight|denoise)$',
          ).hasMatch(plain) ||
          RegExp(
            r'^comfy_(create|edit)_(workflow_id|model_choices|uploaded_workflow)$',
          ).hasMatch(plain) ||
          RegExp(
            r'^draw_things_(grpc_host|grpc_port|sampler|shift|seed_mode|tea_cache|cfg_zero_star)$',
          ).hasMatch(plain) ||
          plain == 'comfy_ui_url' ||
          plain == 'local_image_gen_url';
    }).toList()..sort();
    return {
      'root': folder.parent.path,
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

  Directory get folder => Directory(
    p.join(storage.rootPath ?? storage.binDir.parent.path, 'ImageBatches'),
  );

  String? rootMoveBlocker() =>
      (!loaded && !loadFailed) || running || working || pendingWrites > 0
      ? 'Finish the current image batch operation before moving the data directory.'
      : null;

  void requireRootStable() {
    if (loadFailed) {
      throw StateError('Retry loading the image queue before using it.');
    }
    if (storage.rootRelocation.isMoving) {
      throw StateError('Wait for the data directory move to finish.');
    }
  }

  void rootChanged() {
    if (!loaded || storedRoot == folder.parent.path) return;
    for (final job in jobs) {
      final config = job.data['config'] as Map<String, dynamic>;
      if (config['root'] == storedRoot) config['root'] = folder.parent.path;
    }
    storedRoot = folder.parent.path;
    changed();
  }

  File file(String name) {
    if (!RegExp(r'^[a-f0-9-]+\.png$').hasMatch(name)) {
      throw FormatException('Invalid batch image name');
    }
    return File(p.join(folder.path, name));
  }

  Future<void> load() async {
    loaded = false;
    await storage.initialized;
    await storage.rootRelocation.settled;
    storedRoot = folder.parent.path;
    await folder.create(recursive: true);
    final manifest = File(p.join(folder.path, 'queue.json'));
    if (!await manifest.exists()) {
      loaded = true;
      return;
    }
    final data = jsonDecode(await manifest.readAsString());
    if (data is! Map || data['jobs'] is! List) {
      throw const FormatException('The image queue is corrupt.');
    }
    final recovered = <ImageBatchJob>[];
    if (data['version'] != 1) {
      throw StateError('Unsupported image batch format.');
    }
    for (final value in data['jobs'] as List) {
      final job = ImageBatchJob(Map<String, dynamic>.from(value as Map));
      for (final key in [
        'id',
        'characterId',
        'characterName',
        'kind',
        'label',
        'prompt',
        'state',
        'negativePrompt',
        'size',
      ]) {
        if (job.data[key] is! String) {
          throw const FormatException(
            'The image queue has an invalid request.',
          );
        }
      }
      if (job.data['config'] is! Map ||
          job.data['seed'] is! int ||
          job.data['denoise'] is! num ||
          ![
            'waiting',
            'running',
            'review',
            'saved',
            'discarded',
            'failed',
            'interrupted',
          ].contains(job.state)) {
        throw const FormatException('The image queue has invalid parameters.');
      }
      if (job.state == 'running') {
        job.data.addAll({
          'state': 'interrupted',
          'error':
              'The app closed during this request. Check the backend before preparing another pass.',
        });
      }
      final config = job.data['config'] as Map<String, dynamic>;
      final origin = data['root'] ?? config['root'];
      if (config['root'] == origin) config['root'] = folder.parent.path;
      recovered.add(job);
    }
    jobs
      ..clear()
      ..addAll(recovered);
    loaded = true;
    await clean();
    changed();
  }

  Future<void> persist() {
    if (loadFailed) {
      throw StateError(
        'The unreadable queue is preserved; retry loading before saving.',
      );
    }
    final content = jsonEncode({
      'version': 1,
      'root': folder.parent.path,
      'jobs': [for (final j in jobs) j.data],
    });
    pendingWrites++;
    final next = writes.then((_) async {
      final temp = File(p.join(folder.path, 'queue.json.tmp'));
      await temp.writeAsString(content, flush: true);
      await temp.rename(p.join(folder.path, 'queue.json'));
    });
    writes = next.then<void>(
      (_) {},
      onError: (Object e) {
        error = 'Could not save the image queue: $e';
        pauseRequested = true;
        changed();
      },
    );
    changed();
    return next.whenComplete(() => pendingWrites--);
  }

  Future<void> clean() async {
    final finished = jobs
        .where((j) => ['saved', 'discarded'].contains(j.state))
        .toList();
    for (final old in finished.take(
      (finished.length - 100).clamp(0, finished.length),
    )) {
      jobs.remove(old);
    }
    final needed = <String>{
      for (final job in jobs.where(
        (j) => !['saved', 'discarded'].contains(j.state),
      ))
        for (final key in ['source', 'candidate'])
          if (job.data[key] is String) job.data[key] as String,
    };
    if (!await folder.exists()) return;
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is File &&
          RegExp(r'^[a-f0-9-]+\.png$').hasMatch(p.basename(entry.path)) &&
          !needed.contains(p.basename(entry.path))) {
        await entry.delete();
      }
    }
  }

  Future<void> ensureCapacity(int bytes) async {
    var total = bytes;
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is File && p.extension(entry.path) == '.png') {
        total += await entry.length();
      }
    }
    if (total > 512 * 1024 * 1024) {
      throw StateError(
        'Image batch storage reached 512 MiB. Save or discard results before continuing.',
      );
    }
  }
}
