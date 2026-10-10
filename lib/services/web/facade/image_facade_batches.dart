// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

extension ImageFacadeBatches on ImageFacade {
  ImageBatchService get batches => _image.batches;
  Future<void> prepareBatch(Map<String, dynamic> body) async {
    final repo = _characters;
    if (repo == null) throw StateError('Character library unavailable.');
    await batches.prepare(
      repository: repo,
      characterIds: List<String>.from(body['characterIds'] as List),
      kind: body['kind'] as String,
      prompt: body['prompt'] as String? ?? '',
      edit: body['edit'] == true,
      missingOnly: body['missingOnly'] != false,
      denoise: (body['denoise'] as num?)?.toDouble(),
      fullSet: body['set'] == 'full',
      promptRules: _readPromptRules(body),
    );
  }

  Future<Map<String, Object>> previewBatchPrompts(
    Map<String, dynamic> body,
  ) async {
    final rules = _readPromptRules(body);
    final card = body['characterId'] is String
        ? await _characters?.getCharacterCardById(body['characterId'] as String)
        : null;
    final prompt = body['prompt'] as String? ?? '';
    final base = imageBatchBasePrompt(
      prompt,
      card?.name ?? 'Character',
      card?.description ?? '',
    );
    final emotions = body['set'] == 'full'
        ? kFullExpressionSet
        : kCuratedExpressionSet;
    return {
      'previews': [
        for (final emotion in emotions)
          {
            'emotion': emotion,
            'original': originalExpressionPrompt(
              emotion: emotion,
              basePrompt: base,
              editMode: packConfigMode == 'edit',
            ),
            'effective': composeExpressionPrompt(
              emotion: emotion,
              basePrompt: base,
              editMode: packConfigMode == 'edit',
              rules: rules,
            ),
          },
      ],
    };
  }

  Future<void> saveBatch() async {
    final repo = _characters;
    if (repo == null) throw StateError('Character library unavailable.');
    await batches.saveKept(repo);
  }
}
