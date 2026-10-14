// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'image_pack_rules.dart';

class ImageBatchesFacade {
  ImageBatchesFacade(this._image, this._storage, this._characters, this._rules);
  final ImageGenService _image;
  final StorageService _storage;
  final CharacterRepository? _characters;
  final ImageStudioPackRules _rules;
  ImageBatchService get batches => _image.batches;
  Future<void> prepareBatch(Map<String, dynamic> body) async {
    final ids = body['characterIds'];
    if (ids is! List ||
        ids.any((id) => id is! String) ||
        body['kind'] is! String ||
        body['prompt'] != null && body['prompt'] is! String) {
      throw const FormatException(
        'Provide character IDs, a save destination and a prompt.',
      );
    }
    for (final key in ['edit', 'missingOnly']) {
      if (body.containsKey(key) && body[key] is! bool) {
        throw FormatException('$key must be boolean.');
      }
    }
    if (body['denoise'] != null && body['denoise'] is! num) {
      throw const FormatException('Strength must be a number.');
    }
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
      promptRules: _rules.readPromptRules(body),
    );
  }

  Future<Map<String, Object>> previewBatchPrompts(
    Map<String, dynamic> body,
  ) async {
    final rules = _rules.readPromptRules(body);
    final card = body['characterId'] is String
        ? await _characters?.getCharacterCardById(body['characterId'] as String)
        : null;
    final prompt = body['prompt'] as String? ?? '';
    final base = imageBatchBasePrompt(
      prompt,
      card?.name ?? 'Character',
      card?.description ?? '',
    );
    final editMode = (await planExpressionPack(_storage)).edit;
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
              editMode: editMode,
            ),
            'effective': composeExpressionPrompt(
              emotion: emotion,
              basePrompt: base,
              editMode: editMode,
              rules: rules,
            ),
          },
      ],
    };
  }

  Future<void> reviewBatch(String id, Map<String, dynamic> body) =>
      batches.decide(
        id,
        body['action'] as String,
        prompt: body['prompt'] as String?,
        newSeed: body['newSeed'] != false,
        repository: _characters,
      );

  Future<void> saveBatch() async {
    final repo = _characters;
    if (repo == null) throw StateError('Character library unavailable.');
    await batches.saveKept(repo);
  }
}
