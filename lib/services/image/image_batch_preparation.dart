// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';

import 'image_batch_store.dart';
import '../expression_pack_base.dart';
import '../expression_pack_prepare.dart';

class ImageBatchPreparation {
  ImageBatchPreparation(this.store);
  final ImageBatchStore store;

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
  }) async {
    await store.ready;
    store.repository = repository;
    store.requireRootStable();
    if (store.working || store.running) throw StateError('The queue is busy.');
    if (!['portrait', 'expressions', 'additional'].contains(kind)) {
      throw ArgumentError('Unknown save destination');
    }
    if (characterIds.isEmpty || characterIds.length > 100) {
      throw ArgumentError('Choose between 1 and 100 characters.');
    }
    if (prompt.length > 16000) throw ArgumentError('Prompt is too long.');
    if (kind == 'additional' && prompt.trim().isEmpty) {
      throw ArgumentError('Describe the additional portrait.');
    }
    final strength = denoise ?? store.storage.imageGenSettings.imageGenDenoise;
    if (!strength.isFinite || strength < 0 || strength > 1) {
      throw ArgumentError('Strength must be between 0 and 1.');
    }
    final rules =
        (promptRules ?? store.storage.expressionSettings.expressionPromptRules)
            .copy();
    final config = store.snapshot();
    store.working = true;
    store.changed();
    final prepared = <ImageBatchJob>[];
    try {
      final plan = kind == 'expressions'
          ? await planExpressionPack(store.storage)
          : null;
      if (plan != null && !plan.canStart) {
        throw StateError(plan.refusal ?? 'Edit configuration is not ready.');
      }
      final useEdit = plan?.edit ?? edit;
      final report = await checkStudioReady(
        settings: store.storage.imageGenSettings,
        edit: useEdit,
      );
      if (!report.ready) {
        throw StateError(
          packNotReadyMessage(
            report.readiness,
            store.storage.imageGenSettings.comfyUiUrl,
          ),
        );
      }
      if (jsonEncode(config) != jsonEncode(store.snapshot())) {
        throw StateError(
          'Settings changed during readiness checks. Prepare again.',
        );
      }
      for (final id in characterIds.toSet()) {
        final sharedSeed = store.storage.imageGenSettings.imageGenSeed < 0
            ? Random.secure().nextInt(0x7fffffff)
            : store.storage.imageGenSettings.imageGenSeed;
        final card = await repository.getActiveCharacterCardById(id);
        if (card == null) {
          throw StateError('A selected character no longer exists.');
        }
        final existing = missingOnly && kind == 'expressions'
            ? (await repository.getAvatarImages(id)).map((a) => a.label).toSet()
            : <String?>{};
        final labels =
            (kind == 'expressions'
                    ? (fullSet ? kFullExpressionSet : kCuratedExpressionSet)
                    : [
                        kind == 'additional'
                            ? 'Additional portrait'
                            : 'Primary portrait',
                      ])
                .where((label) => !existing.contains(label))
                .toList();
        if (labels.isEmpty) continue;
        String? source;
        if (useEdit || kind == 'expressions') {
          final base = await packCurrentPortraitImage(
            repository,
            store.storage,
            id,
          );
          if (base == null) {
            throw StateError('${card.name} needs a source portrait.');
          }
          final normalized = await preparePackBase(base);
          if (normalized == null) {
            throw StateError('${card.name} has an unreadable source portrait.');
          }
          source = '${const Uuid().v4()}.png';
          await store.ensureCapacity(normalized.bytes.length);
          await store.file(source).writeAsBytes(normalized.bytes, flush: true);
        }
        for (final label in labels) {
          final basePrompt = imageBatchBasePrompt(
            prompt,
            card.name,
            card.description,
          );
          final effective = kind == 'expressions'
              ? composeExpressionPrompt(
                  emotion: label,
                  basePrompt: basePrompt,
                  editMode: useEdit,
                  rules: rules,
                )
              : basePrompt;
          final negative =
              store.storage.imageGenSettings.imageGenNegativePrompt;
          if (prepared.length + store.jobs.length >= 1024) {
            throw StateError('Prepare up to 1024 queued requests at a time.');
          }
          prepared.add(
            ImageBatchJob({
              'id': const Uuid().v4(),
              'characterId': id,
              'characterName': card.name,
              'kind': kind,
              'label': label,
              'prompt': effective,
              'negativePrompt': imageBatchNegativePrompt(
                negative,
                kind == 'expressions' ? label : null,
              ),
              'seed': sharedSeed,
              'denoise': strength,
              'denoiseOverride': denoise,
              'size': store.storage.imageGenSettings.imageGenSize,
              'edit': useEdit,
              'source': source,
              'config': config,
              'state': 'waiting',
              'kept': false,
            }),
          );
        }
      }
      if (jsonEncode(config) != jsonEncode(store.snapshot())) {
        throw StateError('Settings changed during preparation. Prepare again.');
      }
      store.jobs.addAll(prepared);
      await store.persist();
    } finally {
      await store.clean();
      store.working = false;
      store.changed();
    }
  }
}
