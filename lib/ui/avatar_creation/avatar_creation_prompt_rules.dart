// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'avatar_creation_controller.dart';

extension AvatarCreationPromptRules on AvatarCreationController {
  ExpressionPromptRules get packPromptRules =>
      _packPromptRules ?? storage.expressionSettings.expressionPromptRules;

  void setPackPromptRules(ExpressionPromptRules rules) {
    if (running) {
      throw StateError('Stop the pack before changing its prompt rules.');
    }
    _packPromptRules = rules.copy();
    _notify();
  }
}
