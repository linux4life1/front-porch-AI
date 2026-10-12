// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/services.dart';

import '../expression_pack_setup.dart';

/// The pack's setup step, before a session exists: the scrolling
/// [ExpressionPackSetup] with the per-emotion original prompts it previews.
class ExpressionPackSetupPane extends StatelessWidget {
  const ExpressionPackSetupPane({
    super.key,
    required this.storage,
    required this.preparingPrompt,
    required this.promptRules,
    required this.onRulesChanged,
    required this.basePrompt,
    required this.baseImage,
    required this.characterName,
    required this.existingEmotions,
    required this.note,
    required this.onCancel,
    required this.onStart,
  });

  final StorageService storage;
  final bool preparingPrompt;
  final ExpressionPromptRules promptRules;
  final ValueChanged<ExpressionPromptRules> onRulesChanged;
  final String basePrompt;
  final Uint8List baseImage;
  final String characterName;
  final Set<String> existingEmotions;
  final String? note;
  final VoidCallback onCancel;
  final void Function({
    required bool fullSet,
    required double denoise,
    required bool replaceExisting,
    required bool skipExisting,
  })
  onStart;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ExpressionPackSetup(
        busy: preparingPrompt || context.watch<ImageGenService>().isGenerating,
        promptRules: promptRules,
        onRulesChanged: onRulesChanged,
        originalPrompts: {
          for (final emotion in kFullExpressionSet)
            emotion: originalExpressionPrompt(
              emotion: emotion,
              basePrompt: '$basePrompt, $kExpressionFraming',
              editMode:
                  ImageGenBackend.fromKey(
                        storage.imageGenSettings.imageGenBackend,
                      ) ==
                      ImageGenBackend.comfyUi ||
                  ImageReferenceResolver.packEditMode(storage.imageGenSettings),
            ),
        },
        baseImage: baseImage,
        characterName: characterName,
        existingEmotions: existingEmotions,
        note: note,
        storage: storage,
        onCancel: onCancel,
        onStart: onStart,
      ),
    );
  }
}
