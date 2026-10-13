// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'image_prompt/image_prompt.dart';

class ExpressionIntensityState {
  ExpressionIntensityState(this.value);
  ExpressionIntensity value;

  String prompt({
    required String emotion,
    required String basePrompt,
    required bool editMode,
    required ExpressionPromptRules rules,
    required ExpressionIntensity level,
  }) => rules.apply(
    originalExpressionPrompt(
      emotion: emotion,
      basePrompt: basePrompt,
      editMode: editMode,
      intensity: level,
    ),
  );
}
