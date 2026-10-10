// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_batch_service.dart';

extension ImageBatchPrepare on ImageBatchService {
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
    await ready;
    _requireRootStable();
    if (working || running) throw StateError('The queue is busy.');
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
    final strength = denoise ?? storage.imageGenSettings.imageGenDenoise;
    if (!strength.isFinite || strength < 0 || strength > 1) {
      throw ArgumentError('Strength must be between 0 and 1.');
    }
    final rules =
        (promptRules ?? storage.expressionSettings.expressionPromptRules)
            .copy();
    final config = snapshot();
    working = true;
    _changed();
    final prepared = <ImageBatchJob>[];
    try {
      final plan = kind == 'expressions'
          ? await planExpressionPack(storage)
          : null;
      if (plan != null && !plan.canStart) {
        throw StateError(plan.refusal ?? 'Edit configuration is not ready.');
      }
      final useEdit = plan?.edit ?? edit;
      final report = await checkStudioReady(
        settings: storage.imageGenSettings,
        edit: useEdit,
      );
      if (!report.ready) {
        throw StateError(
          packNotReadyMessage(
            report.readiness,
            storage.imageGenSettings.comfyUiUrl,
          ),
        );
      }
      if (jsonEncode(config) != jsonEncode(snapshot())) {
        throw StateError(
          'Settings changed during readiness checks. Prepare again.',
        );
      }
      for (final id in characterIds.toSet()) {
        final sharedSeed = storage.imageGenSettings.imageGenSeed < 0
            ? Random.secure().nextInt(0x7fffffff)
            : storage.imageGenSettings.imageGenSeed;
        final card = await repository.getActiveCharacterCardById(id);
        if (card == null) {
          throw StateError('A selected character no longer exists.');
        }
        String? source;
        if (useEdit || kind == 'expressions') {
          final base = await packCurrentPortraitImage(repository, storage, id);
          if (base == null) {
            throw StateError('${card.name} needs a source portrait.');
          }
          final normalized = await preparePackBase(base);
          if (normalized == null) {
            throw StateError('${card.name} has an unreadable source portrait.');
          }
          source = '${const Uuid().v4()}.png';
          await _file(source).writeAsBytes(normalized.bytes, flush: true);
        }
        final existing = missingOnly && kind == 'expressions'
            ? (await repository.getAvatarImages(id)).map((a) => a.label).toSet()
            : <String?>{};
        for (final label
            in kind == 'expressions'
                ? (fullSet ? kFullExpressionSet : kCuratedExpressionSet)
                : [
                    kind == 'additional'
                        ? 'Additional portrait'
                        : 'Primary portrait',
                  ]) {
          if (existing.contains(label)) continue;
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
          final negative = storage.imageGenSettings.imageGenNegativePrompt;
          final counter = kind == 'expressions'
              ? kExpressionNegatives[label] ?? ''
              : '';
          prepared.add(
            ImageBatchJob({
              'id': const Uuid().v4(),
              'characterId': id,
              'characterName': card.name,
              'kind': kind,
              'label': label,
              'prompt': effective,
              'negativePrompt': [
                negative,
                counter,
              ].where((s) => s.trim().isNotEmpty).join(', '),
              'seed': sharedSeed,
              'denoise': strength,
              'size': storage.imageGenSettings.imageGenSize,
              'edit': useEdit,
              'source': source,
              'config': config,
              'state': 'waiting',
              'kept': false,
            }),
          );
        }
      }
      if (jsonEncode(config) != jsonEncode(snapshot())) {
        throw StateError('Settings changed during preparation. Prepare again.');
      }
      _jobs.addAll(prepared);
      await _persist();
    } finally {
      working = false;
      _changed();
    }
  }
}
