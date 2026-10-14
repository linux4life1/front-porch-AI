// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

import 'image_batch_store.dart';
import 'image_batch_preparation.dart';
import 'image_batch_review.dart';

class ImageBatchService extends ChangeNotifier {
  ImageBatchService(this.storage, this.image) {
    store = ImageBatchStore(storage, image, notifyListeners);
    _prepare = ImageBatchPreparation(store);
    _review = ImageBatchReview(store);
  }
  final StorageService storage;
  final ImageGenService image;
  late final ImageBatchStore store;
  late final ImageBatchPreparation _prepare;
  late final ImageBatchReview _review;
  Future<void> get ready => store.ready;
  List<ImageBatchJob> get jobs => List.unmodifiable(store.jobs);
  bool get running => store.running;
  bool get working => store.working;
  bool get pauseRequested => store.pauseRequested;
  String? get error => store.error;
  bool get loadFailed => store.loadFailed;
  Map<String, dynamic> snapshot() => store.snapshot();
  ImageBatchJob job(String id) => _review.job(id);
  Future<Uint8List> picture(String id) => _review.picture(id);
  Future<void> prepare({
    required CharacterRepository repository,
    required List<String> characterIds,
    required String kind,
    required String prompt,
    bool edit = false,
    bool missingOnly = true,
    double? denoise,
    bool fullSet = false,
    ExpressionPromptRules? promptRules,
  }) => _prepare.prepare(
    repository: repository,
    characterIds: characterIds,
    kind: kind,
    prompt: prompt,
    edit: edit,
    missingOnly: missingOnly,
    denoise: denoise,
    fullSet: fullSet,
    promptRules: promptRules,
  );
  Future<void> decide(
    String id,
    String action, {
    String? prompt,
    bool newSeed = true,
    CharacterRepository? repository,
  }) {
    store.repository = repository ?? store.repository;
    return _review.decide(id, action, prompt: prompt, newSeed: newSeed);
  }

  Future<void> saveKept(CharacterRepository repository) =>
      _review.saveKept(repository);
  Future<void> retryLoad() {
    if (running || working) throw StateError('Queue is busy.');
    store.ready = store.reload();
    return store.ready;
  }

  void pause() {
    store.pauseRequested = true;
    store.changed();
  }

  void reportError(Object problem) {
    store.error = '$problem';
    store.changed();
  }

  Map<String, dynamic> view() => {
    'running': running,
    'working': working,
    'loadFailed': loadFailed,
    'pauseRequested': pauseRequested,
    'error': error,
    'jobs': [for (final job in jobs) job.view()],
  };
  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  void checkCanRun() {
    store.requireRootStable();
    if (store.running || store.working || store.image.isGenerating) {
      throw StateError('Another image operation is busy.');
    }
    if (expressionPackBoard.run != null) {
      throw StateError('Finish or discard the current expression pack first.');
    }
  }

  Future<void> run() async {
    await store.ready;
    checkCanRun();
    store.running = true;
    store.pauseRequested = false;
    store.error = null;
    store.changed();
    try {
      final started = await ImageGenService.startExpressionPackOn(store.image, [], (
        _,
      ) async {
        for (final job
            in store.jobs.where((j) => j.state == 'waiting').toList()) {
          if (store.pauseRequested) break;
          if (job.state != 'waiting') continue;
          if (jsonEncode(job.data['config']) != jsonEncode(store.snapshot())) {
            store.error =
                'Image settings changed. Restore the captured configuration or prepare another pass.';
            break;
          }
          job.data['state'] = 'running';
          try {
            await store.persist();
            final source = job.data['source'] as String?;
            final bytes = await ImageGenService.expressionFrameOn(
              store.image,
              prompt: job.prompt,
              negativePrompt: job.data['negativePrompt'] as String,
              size: job.data['size'] as String,
              referenceImage: source == null
                  ? null
                  : await store.file(source).readAsBytes(),
              seed: job.data['seed'] as int,
              denoise: (job.data['denoise'] as num).toDouble(),
              intent: job.edit ? StudioIntent.edit : StudioIntent.create,
              editStrength: job.edit
                  ? (job.data['denoise'] as num).toDouble()
                  : null,
            );
            if (bytes == null) {
              throw StateError(
                store.image.statusMessage.isEmpty
                    ? 'Generation returned no image.'
                    : store.image.statusMessage,
              );
            }
            final normalized = await imageBatchPixels(bytes);
            if (normalized == null) {
              throw StateError('Generation returned an unreadable image.');
            }
            final name = '${job.id}.png';
            await store.ensureCapacity(normalized.length);
            await store.file(name).writeAsBytes(normalized, flush: true);
            job.data.addAll({
              'state': 'review',
              'candidate': name,
              'error': null,
            });
          } catch (e) {
            job.data.addAll({'state': 'failed', 'error': '$e'});
            store.error =
                'Generation stopped. Review the failed request before continuing.';
            store.pauseRequested = true;
          }
          await store.persist();
        }
        return <String>[];
      });
      if (started == null) {
        throw StateError('Another generation acquired the image service.');
      }
    } finally {
      store.running = false;
      store.pauseRequested = false;
      store.changed();
    }
  }
}
