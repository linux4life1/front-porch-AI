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

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

/// Immutable, typed context bag for image prompt generation.
///
/// Collects only the information that is *useful for producing visual prompts*:
/// - Character appearance (never full personality blobs for portraits).
/// - Narrative elements that can be distilled into scene/action/pose/lighting.
/// - Environment/setting (for backgrounds and scene establishment).
/// - User persona (only for userAvatar mode).
/// - Optional hints for expression/pose, time-of-day lighting, group speaker targeting.
/// - userInstruction: free text typed in studio box before Craft (sent to LLM to parse into visual prompt).
///
/// The builder owns all distillation rules. This bag is intentionally "dumb" data +
/// a couple of safe helpers (macro resolution, truncation). Callers supply the best
/// raw material they have; the builder decides what is visual vs. irrelevant.
///
/// Used by ImagePromptBuilder (the single source of truth for mode semantics and
/// style enforcement). See image_prompt_builder.dart for the contracts of each mode.
/// For customPrompt, [recentMessages] is the scene source the builder distills when the
/// user's typed prompt ([lastMessage]) is empty.
/// Keep ctor / toString / usage in sync with service _buildPromptContext (thin), studio craft/ctor,
/// chat_page _show collection, builder _generateSmartWith + _buildStatic. (per-invocation snapshot).
class ImageGenContext {
  final ImageGenMode mode;
  final String style; // 'photorealistic' | 'anime' | 'fantasy_art' ...
  final String
  paradigm; // 'natural' | 'tags' (from storage.imageGenPromptParadigm)

  // Core visual identity
  final String? characterName;
  final String? characterDescription; // appearance-focused only (card desc)
  final String?
  currentExpression; // short visual/pose hint if available (e.g. "smiling warmly, hand on hip")

  // Scene / narrative source material (builder will *distill*, never dump raw)
  final String?
  lastMessage; // the raw displayText of the last message (usually the narrative to illustrate)
  final List<String>?
  recentMessages; // up to ~5 prior for "recent events" context (still distilled)
  final String?
  scenario; // used primarily for environment / time / location cues
  final String? worldInfo; // setting / atmosphere seed (environment only)

  // User side (userAvatar mode + macro resolution)
  final String? personaName;
  final String? personaText; // appearance description for the user's persona

  // Group / targeting hints (used for correct character focus under impersonation)
  final bool isGroupNonObserver;
  final String?
  currentSpeakerId; // or name; builder uses for "which char is acting" in fromLast/visualize

  // Optional lighting / atmosphere hints (from realism time or explicit)
  final String? timeOfDay; // e.g. "evening", "midnight", "golden hour"
  final String?
  lightingHint; // free-form extra (e.g. "candlelight", "neon rain")

  // User spec (Stage 4 continuation): free-form text the user typed in the studio prompt box
  // before tapping Craft/Refresh. Passed through to LLM as additional instruction so it
  // "parses into the image gen prompt". Included for all modes on craft path.
  final String? userInstruction;

  const ImageGenContext({
    required this.mode,
    required this.style,
    required this.paradigm,
    this.characterName,
    this.characterDescription,
    this.currentExpression,
    this.lastMessage,
    this.recentMessages,
    this.scenario,
    this.worldInfo,
    this.personaName,
    this.personaText,
    this.isGroupNonObserver = false,
    this.currentSpeakerId,
    this.timeOfDay,
    this.lightingHint,
    this.userInstruction,
  });

  /// Resolve {{user}} / {{char}} (and common variants) in any source text.
  /// Safe no-op on null/empty.
  String resolveMacros(String? text) {
    if (text == null || text.isEmpty) return '';
    return MacroResolver().resolve(
      text,
      MacroContext(
        userName: personaName ?? 'User',
        characterName: characterName ?? 'Character',
      ),
    );
  }

  /// Truncate helper that tries to break at a word boundary.
  /// (Duplicated from old service logic for self-containment of the builder module;
  /// the service version can be deleted in Stage 2.)
  static String truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    final cut = text.substring(0, maxLen);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > maxLen ~/ 2) {
      return '${cut.substring(0, lastSpace)}...';
    }
    return '$cut...';
  }

  /// Convenience: the "best" character visual description for portrait mode.
  /// Never includes personality.
  String get effectiveCharacterAppearance {
    final desc = characterDescription?.trim() ?? '';
    if (currentExpression != null && currentExpression!.isNotEmpty) {
      return desc.isNotEmpty
          ? '$desc, ${currentExpression!.trim()}'
          : currentExpression!.trim();
    }
    return desc;
  }

  @override
  String toString() =>
      'ImageGenContext(mode: $mode, style: $style, paradigm: $paradigm, '
      'char: ${characterName ?? "none"}, lastMsgLen: ${lastMessage?.length ?? 0}, '
      'userInstr: ${userInstruction != null})';
}
