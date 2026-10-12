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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_gen_context.dart';

import '../image_prompt_builder.dart'
    show cleanNarrativeForVisual, kImagePromptSceneRecentCap;

/// The static (no-LLM) prompt body for [ctx], before style enforcement and
/// the length cap.
String buildStaticImagePrompt(ImageGenContext ctx) {
  String resolved(String? t) => ctx.resolveMacros(t);
  final parts = <String>[];

  switch (ctx.mode) {
    case ImageGenMode.characterPortrait:
      if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
        parts.add('Character portrait of ${ctx.characterName}.');
      }
      final app = ctx.effectiveCharacterAppearance;
      if (app.isNotEmpty) {
        parts.add(ImageGenContext.truncate(resolved(app), 380));
      }
      parts.add(
        'Detailed close-up portrait, expressive face, high quality rendering, sharp focus on features and clothing.',
      );

    case ImageGenMode.userAvatar:
      if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
        parts.add('Portrait of ${ctx.personaName}.');
      }
      if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
        parts.add(ImageGenContext.truncate(resolved(ctx.personaText), 380));
      }
      if (ctx.currentExpression != null && ctx.currentExpression!.isNotEmpty) {
        parts.add(resolved(ctx.currentExpression));
      }
      parts.add(
        'Detailed close-up portrait, expressive face, high quality rendering.',
      );

    case ImageGenMode.customPrompt:
      // Text present → verbatim (buildPrompt already short-circuits this before
      // reaching here; kept for direct buildStaticPrompt callers).
      final raw = (ctx.lastMessage ?? '').trim();
      if (raw.isNotEmpty) return raw;

      // Empty text → distill the CURRENT SCENE from the recent narrative.
      // The recent turns (what is actually happening right now) are the primary
      // content; character appearance grounds it. Scenario/world are omitted
      // (they led to the disliked "Scene setting: <dump>" framing).
      if (ctx.characterDescription != null &&
          ctx.characterDescription!.isNotEmpty) {
        parts.add(
          'Key character appearance: ${ImageGenContext.truncate(resolved(ctx.characterDescription), 200)}',
        );
      }
      if (ctx.currentExpression != null && ctx.currentExpression!.isNotEmpty) {
        parts.add(
          'Current expression / pose: ${resolved(ctx.currentExpression)}',
        );
      }
      if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
        parts.add('User: ${ctx.personaName}');
        if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
          parts.add(
            'User persona: ${ImageGenContext.truncate(resolved(ctx.personaText), 120)}',
          );
        }
      }
      if (ctx.userInstruction != null &&
          ctx.userInstruction!.trim().isNotEmpty) {
        parts.add(
          'User guidance: ${ImageGenContext.truncate(resolved(ctx.userInstruction), 120)}',
        );
      }
      if (ctx.recentMessages != null && ctx.recentMessages!.isNotEmpty) {
        List<String> src = ctx.recentMessages!;
        if (src.length > kImagePromptSceneRecentCap) {
          src = src.sublist(src.length - kImagePromptSceneRecentCap);
        }
        final recent = src
            .map(
              (m) => ImageGenContext.truncate(
                cleanNarrativeForVisual(resolved(m)),
                120,
              ),
            )
            .where((m) => m.isNotEmpty)
            .join(' ');
        if (recent.isNotEmpty) {
          parts.add(
            'Recent visual events (stripped): ${ImageGenContext.truncate(recent, 220)}',
          );
        }
      }
      if (ctx.timeOfDay != null && ctx.timeOfDay!.isNotEmpty) {
        parts.add('Time / lighting: ${ctx.timeOfDay}');
      }
      if (ctx.lightingHint != null && ctx.lightingHint!.isNotEmpty) {
        parts.add('Lighting detail: ${ctx.lightingHint}');
      }
      if (ctx.isGroupNonObserver &&
          ctx.currentSpeakerId != null &&
          ctx.currentSpeakerId!.isNotEmpty) {
        parts.add('Focus on ${resolved(ctx.currentSpeakerId)}.');
      }
      // Nothing to distill (no narrative supplied) → safe generic scene.
      if (parts.isEmpty) {
        return 'detailed visual scene with strong composition and lighting';
      }
      parts.add(
        'Cinematic wide or medium establishing shot of the scene, clear composition showing characters '
        'present and what they are physically doing, atmospheric lighting.',
      );
  }

  String prompt = parts.where((p) => p.isNotEmpty).join(' ');

  // Strip the known character name from the customPrompt scene distillation so the
  // static prompt respects the "NEVER include character names" rule the LLM path is
  // given. Replaces it with "the character"; other names are best-effort.
  if (ctx.mode == ImageGenMode.customPrompt &&
      ctx.characterName != null &&
      ctx.characterName!.isNotEmpty) {
    final name = RegExp.escape(ctx.characterName!);
    prompt = prompt.replaceAll(
      RegExp('\\b$name\\b', caseSensitive: false),
      'the character',
    );
  }

  return prompt;
}
