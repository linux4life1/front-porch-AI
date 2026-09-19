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

part of 'image_prompt_builder.dart';

extension _ImagePromptBuilders on ImagePromptBuilder {
  Future<String> _generateSmartWith(LLMService llm, ImageGenContext ctx) async {
    final suffix = _getStyleSuffix(ctx.style, ctx.paradigm);
    final isTags = ctx.paradigm == 'tags';

    final formatInstruction = isTags
        ? 'Write a flat, comma-separated list of visual danbooru-style tags describing ONLY the visible scene, characters, clothing, pose, lighting, and environment. NO prose sentences. NO character names. NO dialogue. Example: masterpiece, best quality, 1girl, long silver hair, determined expression, swinging sword, rain-soaked courtyard, moonlight, dynamic action, wet cloak'
        : 'Write ONE vivid paragraph in natural descriptive English. Focus exclusively on what can be seen: appearance, clothing, pose, expression, action, environment, lighting, mood, composition. NO character names. NO spoken dialogue or thoughts. Be specific and cinematic.';

    String modeInstruction;
    switch (ctx.mode) {
      case ImageGenMode.characterPortrait:
        modeInstruction =
            'TASK: Create a tight character portrait prompt. Use ONLY the supplied appearance description '
            'and current expression/pose. Emphasize face, eyes, hair, clothing details, expression, and '
            'a pleasing close-up composition. Do not invent a full-body scene or environment unless it is '
            'minimal and clearly implied by the appearance text.';
      case ImageGenMode.userAvatar:
        modeInstruction =
            'TASK: Portrait of the user character. Use the supplied persona appearance text and any '
            'expression/pose hints. Close-up, expressive, high-quality rendering.';
      case ImageGenMode.customPrompt:
        // Reached only when the typed prompt is empty → distill the current scene.
        modeInstruction =
            'TASK: Describe the CURRENT VISUAL SCENE as a cinematic illustration. '
            'The "Recent messages" block below contains the most recent turns. '
            'These describe what the characters are *actually doing right now* (poses, actions this moment, clothing, spatial relations, mood, lighting). '
            'Base the visual prompt primarily on that recent action and the supplied character appearance. '
            'Who is present, what they are physically doing, wearing, holding, their spatial relationship '
            'to each other and the environment, the lighting (time of day + weather), and overall mood. '
            'Distill from the recent narrative; do not copy dialogue.';
    }

    // Build a compact, visual-only context block (the builder's responsibility to filter).
    // For pure portrait modes we deliberately omit narrative/chat context (recentMessages) so
    // the LLM sees mostly the supplied appearance text. This matches the static path for
    // portraits and the strict "use ONLY the supplied appearance description" instruction.
    // Recent narrative remains available for customPrompt's empty-text scene distillation.
    // Time/lighting hints are still provided for portraits as they help with face lighting.
    final parts = <String>[];
    if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
      parts.add('Primary character: ${ctx.characterName}');
    }
    final app = ctx.effectiveCharacterAppearance;
    if (app.isNotEmpty) {
      parts.add('Appearance: ${ctx.resolveMacros(app)}');
    }

    final isPurePortrait =
        ctx.mode == ImageGenMode.characterPortrait ||
        ctx.mode == ImageGenMode.userAvatar;

    // User spec (no boilerplate/pregen in box; Craft assembles): always surface User persona (name + text) + character visual info
    // (via effectiveAppearance which never includes personality/backstory). The userInstruction (typed box content before Craft)
    // is sent so LLM "parses [it] into the image gen prompt". Style always appended by _ensure at end.
    if (ctx.personaName != null && ctx.personaName!.isNotEmpty) {
      parts.add('User: ${ctx.personaName}');
      if (ctx.personaText != null && ctx.personaText!.isNotEmpty) {
        parts.add('User persona: ${ctx.resolveMacros(ctx.personaText)}');
      }
    }
    // (character appearance block already added unconditionally above via 'Appearance:')

    if (ctx.timeOfDay != null && ctx.timeOfDay!.isNotEmpty) {
      parts.add('Time / lighting: ${ctx.timeOfDay}');
    }
    if (ctx.lightingHint != null && ctx.lightingHint!.isNotEmpty) {
      parts.add('Lighting hint: ${ctx.lightingHint}');
    }
    if (ctx.isGroupNonObserver &&
        ctx.currentSpeakerId != null &&
        ctx.currentSpeakerId!.isNotEmpty &&
        ctx.mode == ImageGenMode.customPrompt) {
      parts.add('Group scene focus / active speaker: ${ctx.currentSpeakerId}');
    }
    // Recent narrative (customPrompt scene distillation only). Messages are
    // pre-generated, so a simple <think>/quote/meta strip is sufficient. Cap to
    // the most recent handful so the context stays tight.
    if (!isPurePortrait &&
        ctx.recentMessages != null &&
        ctx.recentMessages!.isNotEmpty) {
      List<String> src = ctx.recentMessages!;
      if (src.length > ImagePromptBuilder._sceneRecentCap) {
        src = src.sublist(src.length - ImagePromptBuilder._sceneRecentCap);
      }
      final joined = src
          .map((m) => _cleanNarrativeForVisual(ctx.resolveMacros(m)))
          .where((m) => m.isNotEmpty)
          .join('\n');
      if (joined.isNotEmpty) {
        parts.add(
          'Recent messages (most recent turns, <think> stripped for visual distillation):\n$joined',
        );
      }
    }
    // User instruction (typed before Craft) always included when present — LLM instructed to incorporate/parse it.
    if (ctx.userInstruction != null && ctx.userInstruction!.trim().isNotEmpty) {
      parts.add(
        'Additional instructions / guidance from user: ${ctx.resolveMacros(ctx.userInstruction)}',
      );
    }

    final rawContext = ImageGenContext.truncate(parts.join('\n'), 1800);

    final llmPrompt =
        'You are an expert visual prompt engineer for high-quality image models (FLUX, SD3, SDXL, Illustrious, etc.).\n'
        'Your job is to produce a single, concise, highly effective image prompt.\n\n'
        '$formatInstruction\n\n'
        '$modeInstruction\n\n'
        'STRICT RULES:\n'
        '- Keep the final prompt under ~90 words (natural) or ~60 tags.\n'
        '- NEVER include character names in the output prompt.\n'
        '- NEVER include spoken dialogue, quotes, or internal thoughts as text.\n'
        '- For backgrounds: repeat the "no people" rule in the prompt itself.\n'
        '- End the prompt with the art style description.${suffix.isNotEmpty ? " Art style: $suffix" : ""}\n\n'
        'Context (visual material only):\n$rawContext\n\n'
        'Output ONLY the image prompt text. No JSON, no explanations, no markdown, no extra lines.';

    String accumulated = '';
    await for (final token in llm.generateStream(
      GenerationParams(
        prompt: llmPrompt,
        maxLength: 600,
        temperature: 0.25,
        repeatPenalty: 1.0,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        mandatoryReasoningHeadroom: true,
        stopSequences: ['\n\n', '<END>', '</END>', '```'],
      ),
    )) {
      accumulated += token;
    }

    String prompt = accumulated.trim();

    // Robust extraction: strip code fences, take first meaningful block, remove leading labels.
    prompt = prompt
        .replaceAll(RegExp(r'^```[a-z]*\s*'), '')
        .replaceAll(RegExp(r'```$'), '')
        .replaceAll(
          RegExp(r'^(prompt|image prompt|output)[:\s]+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    // Extra belt-and-suspenders cleaning for any leaked think/meta from the model output or bad context.
    // Complements the input cleaning with _cleanNarrativeForVisual on narrative sources.
    prompt = stripThinkForVisual(prompt);
    prompt = prompt.replaceAll(
      RegExp(
        r'Realism evaluation interrupted.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );

    if (prompt.isEmpty) {
      throw Exception('LLM returned empty prompt');
    }

    // If the model ignored the "no names" rule, the caller can still edit in the studio.
    // We do a best-effort name strip here for the common case.
    if (ctx.characterName != null && ctx.characterName!.isNotEmpty) {
      final name = RegExp.escape(ctx.characterName!);
      prompt = prompt.replaceAll(
        RegExp('\\b$name\\b', caseSensitive: false),
        'the character',
      );
    }

    // Best-effort removal of literal spoken dialogue from the model's output.
    // Uses the canonical deduped helper (also used by the static path).
    prompt = stripQuotedSpeech(prompt);

    return prompt;
  }

  String _buildStatic(ImageGenContext ctx) {
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
        if (ctx.currentExpression != null &&
            ctx.currentExpression!.isNotEmpty) {
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
        if (ctx.currentExpression != null &&
            ctx.currentExpression!.isNotEmpty) {
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
          if (src.length > ImagePromptBuilder._sceneRecentCap) {
            src = src.sublist(src.length - ImagePromptBuilder._sceneRecentCap);
          }
          final recent = src
              .map(
                (m) => ImageGenContext.truncate(
                  _cleanNarrativeForVisual(resolved(m)),
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
}
