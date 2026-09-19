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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_gen_context.dart';
import 'package:front_porch_ai/services/image_prompt/visual_source_text.dart';
import 'package:front_porch_ai/utils/utils.dart' show stripQuotedSpeech;

part 'image_prompt_builder.builders.dart';

/// Single source of truth for turning (mode + style + raw context) into a high-quality,
/// style-faithful image generation prompt.
///
/// ## Design
/// - Plain class (no ChangeNotifier, easily testable with or without a real LLMService).
/// - Stateless / prompt-only for the core build path (no owned scalars that need reset).
/// - All "spirit of the mode" contracts live here with explicit documentation.
/// - Style application is centralized and *enforced* (no more fragile post-hoc substring checks).
/// - LLM path (when available) uses stronger instructions + few-shot examples.
/// - Robust fallbacks that are already better than the old static buildPrompt for every mode.
///
/// ## Mode Contracts (the "spirit")
/// - **characterPortrait**: Purely visual appearance + current expression/pose/clothing. Never
///   personality, backstory, or scenario text. "Detailed close-up, expressive face, high quality
///   rendering" + style. Current expression (if supplied) is injected as a strong visual cue.
/// - **customPrompt**: Two behaviors keyed off the typed prompt text ([lastMessage]):
///   - *Text present* → straight-through with style enforcement (the user's exact words).
///   - *Text empty but recent narrative supplied* → distill the CURRENT SCENE from the recent
///     messages: who is present, what they are doing/holding/wearing, spatial relationships,
///     mood, lighting (timeOfDay + hints). Messages are stripped of all `<think>` and quoted
///     dialogue. This is the bare `/image` / `/image scene` behavior (the former standalone
///     "Visualize Scene" mode was folded in here; the older "Message Illustration" mode before
///     that was likewise retired as redundant).
/// - **userAvatar**: Straight-through portrait using personaText as the appearance source
///   (no personality leakage) + style enforcement.
///
/// ## Style Enforcement
/// The builder always produces a final prompt that contains the canonical style suffix for the
/// chosen paradigm. A live preview of the exact suffix is available for the UI (see
/// getStyleSuffix + getStylePreviewNote). Substring hacks are gone.
///
/// ## LLM vs Fallback
/// When an LLMService is supplied and ready, generateSmartPrompt is used (richer instruction +
/// examples). On any failure (stream error, bad parse, empty output) we fall back to a strong
/// static builder that is already an improvement over the pre-refactor logic. The static path
/// is also used for customPrompt (no LLM needed).
///
/// This class is intentionally decoupled from ImageGenService storage and UI. The service
/// (Stage 2) will build an ImageGenContext from the flat parameters it receives today and
/// delegate here. Callers that want the best prompt can construct a context directly in tests
/// or future surfaces.
///
/// See the dedicated test file for many concrete examples of the expected distillation behavior.
class ImagePromptBuilder {
  final LLMService? _llmService;

  // Canonical style suffixes (moved here as the source of truth in Stage 1/2 transition).
  // Natural language versions work across FLUX, SD3, SDXL, and older models.
  static const Map<String, String> styleModifiers = {
    'photorealistic':
        'Photorealistic with cinematic lighting, sharp focus, and highly detailed textures.',
    'anime':
        'Anime-style illustration with clean linework, expressive eyes, vibrant colors, and cel shading.',
    'fantasy_art':
        'Epic fantasy digital art with dramatic lighting, rich environmental detail, and a painterly quality.',
    'oil_painting':
        'Classical oil painting with visible brushstrokes, rich color depth, and fine art composition.',
    'digital_art':
        'Polished digital art with vibrant colors, clean lines, and professional illustration quality.',
    'watercolor':
        'Soft watercolor illustration with flowing color washes, delicate edges, and gentle translucent tones.',
  };

  // Legacy comma/tag versions (for the 'tags' paradigm, primarily SD 1.5 / Illustrious family).
  static const Map<String, String> legacyStyleModifiers = {
    'photorealistic':
        'photorealistic, cinematic lighting, sharp focus, highly detailed, 8k',
    'anime':
        'anime style, masterpiece, best quality, highly detailed, cel shading',
    'fantasy_art':
        'fantasy art, epic, dramatic lighting, highly detailed, painterly',
    'oil_painting': 'oil painting, traditional media, brushstrokes, fine art',
    'digital_art': 'digital art, polished, vibrant, illustration, high quality',
    'watercolor':
        'watercolor, translucent, soft washes, pastel, traditional media',
  };

  static const int _maxPromptLength = 1000;

  /// How many of the most recent messages feed customPrompt's scene distillation.
  static const int _sceneRecentCap = 6;

  ImagePromptBuilder({LLMService? llmService}) : _llmService = llmService;

  /// Main entry. Builds (and style-enforces) a prompt for the given mode using the supplied context.
  /// The context already carries the chosen style and paradigm.
  Future<String> buildPrompt(ImageGenContext ctx) async {
    // customPrompt with real user text → use it verbatim + style (no LLM). When
    // the text is empty we fall through to the smart/static path below, which
    // distills the *current scene* from the supplied recent narrative — this is
    // what the bare `/image` / `/image scene` command relies on (the old
    // standalone "Visualize Scene" mode was folded into customPrompt here).
    if (ctx.mode == ImageGenMode.customPrompt &&
        (ctx.lastMessage ?? '').trim().isNotEmpty) {
      final suffix = _getStyleSuffix(ctx.style, ctx.paradigm);
      final glue = ctx.paradigm == 'tags' ? ', ' : '. ';
      final raw = '${ctx.lastMessage!.trim()}$glue$suffix';
      return ImageGenContext.truncate(raw, _maxPromptLength);
    }

    // LLM path (if available)
    final llm = _llmService;
    if (llm != null && llm.isReady) {
      try {
        final smart = await _generateSmartWith(llm, ctx);
        if (smart.isNotEmpty) {
          return _ensureStyleAndCap(smart, ctx.style, ctx.paradigm);
        }
      } catch (e) {
        debugPrint(
          'ImagePromptBuilder: LLM smart prompt failed ($e) — falling back to static',
        );
      }
    }

    // Strong static fallback (already better than pre-refactor for every mode)
    final fallback = _buildStatic(ctx);
    return _ensureStyleAndCap(fallback, ctx.style, ctx.paradigm);
  }

  /// Returns the exact style suffix that will be appended for (style, paradigm).
  /// UI can use this for live "what will be added" previews.
  String getStyleSuffix(String style, String paradigm) =>
      _getStyleSuffix(style, paradigm);

  /// Synchronous static (no-LLM) prompt for callers that need the old buildPrompt signature.
  /// This is the improved fallback logic only — use [buildPrompt] for the full (LLM+static) experience.
  String buildStaticPrompt(ImageGenContext ctx) {
    final raw = _buildStatic(ctx);
    return _ensureStyleAndCap(raw, ctx.style, ctx.paradigm);
  }

  /// Short human note describing how the style will be applied (for tooltips / help).
  String getStylePreviewNote(String style, String paradigm) {
    final suffix = _getStyleSuffix(style, paradigm);
    return paradigm == 'tags'
        ? 'Tags mode: will be appended as comma-separated visual tags.'
        : 'Natural language: "$suffix"';
  }

  // ─────────────────────────────────────────────────────────────────────
  // Internal implementation
  // ─────────────────────────────────────────────────────────────────────

  String _getStyleSuffix(String style, String paradigm) {
    final map = paradigm == 'tags' ? legacyStyleModifiers : styleModifiers;
    return map[style] ?? '';
  }

  /// Cleans narrative text (last message, recent, scenario, world) for use in visual image prompts.
  /// Combines quote strip + think strip + removal of known non-visual meta (interrupted evals, card import junk).
  /// Keeps the result as source material for distillation rather than raw dump.
  String _cleanNarrativeForVisual(String text) {
    text = stripQuotedSpeech(text);
    text = stripThinkForVisual(text);
    text = text.replaceAll(
      RegExp(
        r'Realism evaluation interrupted.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'Auto-imported from character card:.*?(?:\n|$)',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    return text;
  }

  String _ensureStyleAndCap(String base, String style, String paradigm) {
    String cleaned = base.trim();
    if (paradigm == 'tags') {
      // Tags mode must never have sentence periods.
      cleaned = cleaned.replaceAll('.', ',').replaceAll(RegExp(r',,+'), ',');
    }
    final suffix = _getStyleSuffix(style, paradigm);
    if (suffix.isEmpty) {
      return ImageGenContext.truncate(cleaned, _maxPromptLength);
    }
    final lower = cleaned.toLowerCase();
    final glue = paradigm == 'tags' ? ', ' : '. ';
    // Very tolerant check — if the first ~8 chars of the suffix are present we assume it's there.
    final head = suffix.substring(0, suffix.length.clamp(0, 8)).toLowerCase();
    if (lower.contains(head)) {
      return ImageGenContext.truncate(cleaned, _maxPromptLength);
    }
    // Guard: if no visual base content, avoid leading glue producing ". Photoreal..." boilerplate.
    if (cleaned.isEmpty) {
      return ImageGenContext.truncate(suffix, _maxPromptLength);
    }
    final joined = '$cleaned$glue$suffix';
    return ImageGenContext.truncate(joined, _maxPromptLength);
  }
}
