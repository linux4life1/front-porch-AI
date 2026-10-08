// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

extension ImageStudioPackRules on ImageFacade {
  ExpressionPromptRules _readPromptRules(Map<String, dynamic> f) {
    if (!f.containsKey('promptRules')) {
      return _storage.expressionSettings.expressionPromptRules.copy();
    }
    try {
      return ExpressionPromptRules.fromJson(f['promptRules']);
    } on FormatException catch (e) {
      throw DeskRefused('bad_prompt_rules', e.message);
    }
  }

  Map<String, Object?> packPromptDefaults() =>
      _storage.expressionSettings.expressionPromptRules.toJson();

  Future<Map<String, Object?>> savePackPromptDefaults(
    Map<String, dynamic> f,
  ) async {
    final rules = _readPromptRules(f);
    await _storage.expressionSettings.setExpressionPromptRules(rules);
    return rules.toJson();
  }

  Map<String, Object?> previewPackPrompts(Map<String, dynamic> f) {
    try {
      return _previewPackPrompts(f);
    } on FormatException catch (e) {
      throw DeskRefused('bad_prompt_rules', e.message);
    }
  }

  Map<String, Object?> _previewPackPrompts(Map<String, dynamic> f) {
    final rules = _readPromptRules(f);
    final active = f['activePack'] == true ? _board.run?.session : null;
    if (f['activePack'] == true && active == null) {
      throw const DeskRefused('no_pack', 'No expression pack.', 404);
    }
    final base = '${'${f['prompt'] ?? ''}'.trim()}, $kExpressionFraming';
    final settings = _storage.imageGenSettings;
    final edit =
        ImageGenBackend.fromKey(settings.imageGenBackend) ==
            ImageGenBackend.comfyUi ||
        ImageReferenceResolver.packEditMode(settings);
    final emotions = f['set'] == 'full'
        ? kFullExpressionSet
        : kCuratedExpressionSet;
    return {
      'previews': [
        for (var i = 0; i < (active?.slots.length ?? emotions.length); i++)
          {
            'emotion': active?.slots[i].emotion ?? emotions[i],
            'original':
                active?.originalPromptFor(i) ??
                originalExpressionPrompt(
                  emotion: emotions[i],
                  basePrompt: base,
                  editMode: edit,
                ),
            'effective':
                active?.slots[i].customPrompt ??
                rules.apply(
                  active?.originalPromptFor(i) ??
                      originalExpressionPrompt(
                        emotion: emotions[i],
                        basePrompt: base,
                        editMode: edit,
                      ),
                ),
          },
      ],
    };
  }

  Map<String, Object?> updatePackPromptRules(Map<String, dynamic> f) {
    final run = _board.run;
    if (run == null) {
      throw const DeskRefused('no_pack', 'No expression pack.', 404);
    }
    if (run.origin != PackOrigin.phone) {
      throw const DeskRefused(
        'desktop_pack',
        'Edit this pack on the computer.',
        409,
      );
    }
    if (!f.containsKey('promptRules')) {
      throw const DeskRefused(
        'bad_prompt_rules',
        'Provide promptRules explicitly.',
      );
    }
    final rules = _readPromptRules(f);
    try {
      for (var i = 0; i < run.session.slots.length; i++) {
        rules.apply(run.session.originalPromptFor(i));
      }
    } on FormatException catch (e) {
      throw DeskRefused('bad_prompt_rules', e.message);
    }
    if (!run.session.updatePromptRules(rules)) {
      throw const DeskRefused(
        'running',
        'Stop the pack before editing prompt rules.',
        409,
      );
    }
    return _board.view()!;
  }
}
