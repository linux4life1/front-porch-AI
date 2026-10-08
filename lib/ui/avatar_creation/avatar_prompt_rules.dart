// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_widgets.dart';

import 'avatar_creation_controller.dart';

Future<void> editCreatorPromptRules(
  BuildContext context,
  AvatarCreationController controller,
) async {
  final settings = controller.storage.expressionSettings;
  final edit =
      controller.backend == ImageGenBackend.comfyUi ||
      ImageReferenceResolver.packEditMode(controller.storage.imageGenSettings);
  final rules = await showExpressionPromptRulesEditor(
    context,
    rules: controller.packPromptRules,
    globalDefaults: () => settings.expressionPromptRules,
    saveDefaults: settings.setExpressionPromptRules,
    originals: {
      for (final emotion in controller.chosenSet)
        emotion: originalExpressionPrompt(
          emotion: emotion,
          basePrompt:
              '${controller.promptController.text.trim()}, $kExpressionFraming',
          editMode: edit,
        ),
    },
  );
  if (!context.mounted || rules == null) return;
  if (controller.running) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop the pack before changing its prompt rules.'),
      ),
    );
    return;
  }
  controller.setPackPromptRules(rules);
}
