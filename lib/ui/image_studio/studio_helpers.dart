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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/image_prompt/image_gen_context.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt_builder.dart';

/// Pure helpers extracted from the ImageStudio coordinator to keep the main file
/// under the project 500 LOC cap while preserving behavior and readability.
/// These are stateless and test-friendly.

String getModeLabel(ImageGenMode mode) {
  switch (mode) {
    case ImageGenMode.customPrompt:
      return 'Freeform';
    case ImageGenMode.characterPortrait:
      return 'Character Portrait';
    case ImageGenMode.userAvatar:
      return 'Your Persona';
  }
}

String getAcceptLabel(ImageGenMode mode) {
  switch (mode) {
    case ImageGenMode.characterPortrait:
    case ImageGenMode.userAvatar:
      return 'Set as Avatar';
    case ImageGenMode.customPrompt:
      return '';
  }
}

bool hasAcceptAction(ImageGenMode mode) {
  return mode == ImageGenMode.characterPortrait ||
      mode == ImageGenMode.userAvatar;
}

/// Re-applies the live style suffix to a prompt text (strips stale, appends current).
/// Used by the coordinator on selector changes so the sent prompt reflects the live preview.
/// (computeInitialPrompt was deleted as part of no-boilerplate user spec + anti-accum; no remaining call sites).
String reapplyCurrentStyleSuffix(
  String currentPrompt,
  String selectedStyle,
  String paradigm,
  ImagePromptBuilder builder,
) {
  final suffix = builder.getStyleSuffix(selectedStyle, paradigm);
  if (suffix.isEmpty) return currentPrompt;

  String base = currentPrompt;

  final allKnown = <String>[
    ...ImagePromptBuilder.styleModifiers.values,
    ...ImagePromptBuilder.legacyStyleModifiers.values,
  ];
  for (final s in allKnown) {
    if (s.isNotEmpty) base = base.replaceAll(s, '');
  }
  base = base.replaceAll(RegExp(r'[,.\s]+$'), '').trim();

  final glue = paradigm == 'tags' ? ', ' : '. ';
  // Guard against empty base after strip (prevents leading ". Photoreal..." boilerplate on style change).
  if (base.isEmpty) {
    return ImageGenContext.truncate(suffix, 1000);
  }
  String updated = '$base$glue$suffix'.trim();
  return ImageGenContext.truncate(updated, 1000);
}
