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

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Prompt delegation for [ImageGenService]: assembles the typed
/// [ImageGenContext] and hands it to [ImagePromptBuilder].
class ImageGenPrompts {
  ImageGenPrompts(this._storage);

  final StorageService _storage;

  // Thin delegation hook for prompt construction.
  // Full ownership of ImageGenContext mapping semantics, mode contracts
  // (no-personality portraits, and customPrompt's scene-distillation fallback
  // when the prompt is empty but recent chat narrative is present), style
  // enforcement, LLM smart path, and static fallbacks lives in ImagePromptBuilder.
  // Keep prompt blocks in sync: changes to ctx construction here must be mirrored in
  // any direct ImageGenContext sites and the builder's own
  // _buildStatic / buildPrompt / _generateSmartWith. The builder is stateless/prompt-only
  // (no reset calls needed). ImageGenService owns no prompt scalars that require zeroing
  // on chat startNew / setActive / load (per-call snapshot from _storage is authoritative).
  // See ImagePromptBuilder for the authoritative mode semantics and style rules.
  late final ImagePromptBuilder _promptBuilder = ImagePromptBuilder();

  /// Body of `ImageGenService.generateSmartPrompt` — see the service's
  /// public member for the doc comment.
  Future<String> generateSmartPrompt({
    required ImageGenMode mode,
    required String style,
    LLMService? llmService,
    String? customPrompt,
    String? lastMessage,
    String? characterName,
    String? characterDescription,
    String?
    characterPersonality, // kept for signature compatibility during transition (ignored for visuals)
    String? scenario,
    String? worldInfo,
    String? personaName,
    String? personaText,
    List<String>? recentMessages,
    // Stage 4: richer optional fields for better prompts (expression/pose, time/lighting, group speaker targeting).
    // Forwarded to thin ctx builder. Keep in sync with buildPrompt sig, _buildPromptContext, studio craft/ctor/show, chat_page launch.
    String? currentExpression,
    String? timeOfDay,
    String? lightingHint,
    bool isGroupNonObserver = false,
    String? currentSpeakerId,
    // Text the user typed in the studio box pre-Craft (passed to the LLM as an
    // instruction to "parse into" the image prompt).
    String? userInstruction,
  }) async {
    final paradigm = _storage.imageGenSettings.imageGenPromptParadigm;

    // Build the rich typed context (builder owns all distillation + style rules).
    // Uses the thin coordination helper (see _buildPromptContext) to keep the customPrompt
    // ternary + hint mapping in one place.
    final ctx = _buildPromptContext(
      mode: mode,
      style: style,
      paradigm: paradigm,
      customPrompt: customPrompt,
      lastMessage: lastMessage,
      characterName: characterName,
      characterDescription: characterDescription,
      scenario: scenario,
      worldInfo: worldInfo,
      personaName: personaName,
      personaText: personaText,
      recentMessages: recentMessages,
      // Stage 4 richer fields forwarded (keep in sync with other _build calls, studio, launch site, builder).
      currentExpression: currentExpression,
      timeOfDay: timeOfDay,
      lightingHint: lightingHint,
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: currentSpeakerId,
      userInstruction: userInstruction,
    );

    // Pass an LLM only if the caller supplied a ready one (builder will use it for smart path).
    // We create a fresh builder with the provided LLM for this call so existing call sites that
    // sometimes pass a different llmService continue to work exactly as before.
    final effectiveBuilder = (llmService != null && llmService.isReady)
        ? ImagePromptBuilder(llmService: llmService)
        : _promptBuilder;

    try {
      return await effectiveBuilder.buildPrompt(ctx);
    } catch (e) {
      debugPrint('ImageGen: Builder failed ($e), using ultimate fallback');
      // Ultimate safety fallback (should almost never be reached).
      // Uses the same thin helper for exact parity with happy path (style honored via arg).
      final fbCtx = _buildPromptContext(
        mode: mode,
        style: style,
        paradigm: paradigm,
        customPrompt: customPrompt,
        lastMessage: lastMessage,
        characterName: characterName,
        characterDescription: characterDescription,
        scenario: scenario,
        worldInfo: worldInfo,
        personaName: personaName,
        personaText: personaText,
        recentMessages: recentMessages,
        // Stage 4 richer fields (keep blocks in sync with happy ctx, buildPrompt ctx, studio, chat_page launch, ctx ctor).
        currentExpression: currentExpression,
        timeOfDay: timeOfDay,
        lightingHint: lightingHint,
        isGroupNonObserver: isGroupNonObserver,
        currentSpeakerId: currentSpeakerId,
        userInstruction: userInstruction,
      );
      return effectiveBuilder.buildStaticPrompt(fbCtx);
    }
  }

  /// Build a prompt for the given generation mode.
  ///
  /// Thin delegation to ImagePromptBuilder (full implementation + contracts live there).
  /// Old switch body deleted as part of Stage 2 of the image prompt refactor.
  /// See ImagePromptBuilder for the authoritative mode semantics and style rules.
  /// Keep prompt blocks in sync: this thin + generateSmartPrompt's ctx mapping must stay
  /// aligned with builder._buildStatic + _ensureStyleAndCap. No new _private methods were
  /// added for prompt logic (only the pre-existing _promptBuilder late final hook).
  String buildPrompt({
    required ImageGenMode mode,
    String? customPrompt,
    String? lastMessage,
    String? characterName,
    String? characterDescription,
    String?
    characterPersonality, // signature compat only (personality is never visual)
    String? scenario,
    String? worldInfo,
    String? personaName,
    String? personaText,
    List<String>? recentMessages,
    // Stage 4: richer optional fields (see generateSmartPrompt). Keep ctx construction / studio / launch / builder in sync.
    String? currentExpression,
    String? timeOfDay,
    String? lightingHint,
    bool isGroupNonObserver = false,
    String? currentSpeakerId,
    String? userInstruction,
  }) {
    final paradigm = _storage.imageGenSettings.imageGenPromptParadigm;
    final style = _storage.imageGenSettings.imageGenStyle;

    // Uses the thin coordination helper (dedup; see _buildPromptContext javadoc).
    final ctx = _buildPromptContext(
      mode: mode,
      style: style,
      paradigm: paradigm,
      customPrompt: customPrompt,
      lastMessage: lastMessage,
      characterName: characterName,
      characterDescription: characterDescription,
      scenario: scenario,
      worldInfo: worldInfo,
      personaName: personaName,
      personaText: personaText,
      recentMessages: recentMessages,
      // Stage 4 richer fields forwarded for builder use in static path (keep in sync with generateSmart ctx sites + launch + studio ctx + builder consumption).
      currentExpression: currentExpression,
      timeOfDay: timeOfDay,
      lightingHint: lightingHint,
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: currentSpeakerId,
      userInstruction: userInstruction,
    );

    // buildPrompt remains the synchronous "static quality" path (used by fallbacks and any direct callers).
    // It now gets the improved static builder logic (no LLM). The async generateSmartPrompt
    // is the one that may use the caller's LLM for higher quality.
    try {
      // We added a small sync static helper on the builder in the same change.
      return _promptBuilder.buildStaticPrompt(ctx);
    } catch (_) {
      return (customPrompt ?? lastMessage ?? 'a scene');
    }
  }
}

/// Tiny pure helper: assembles ImageGenContext from the flat params the thins receive.
/// This is *thin coordination/wiring only* — no distillation, no style rules, no LLM,
/// no mode semantics. All of that is in ImagePromptBuilder (the single source of truth).
/// The only "logic" here is the original customPrompt ? customPrompt : lastMessage
/// ternary (plus the paradigm read that was already here). For customPrompt the ctx's
/// lastMessage carries the user's typed text; when that is null/empty the builder
/// distills the current scene from [recentMessages] instead.
/// Keep in sync with ImageGenContext ctor, studio _ctx, the chat_page launch collection,
/// the /image slash-command craft, and builder consumption sites. (ctx is a per-invocation
/// snapshot — no reset semantics apply.)
ImageGenContext _buildPromptContext({
  required ImageGenMode mode,
  required String style,
  required String paradigm,
  String? customPrompt,
  String? lastMessage,
  String? characterName,
  String? characterDescription,
  String? scenario,
  String? worldInfo,
  String? personaName,
  String? personaText,
  List<String>? recentMessages,
  String? currentExpression,
  String? timeOfDay,
  String? lightingHint,
  bool isGroupNonObserver = false,
  String? currentSpeakerId,
  String? userInstruction,
}) {
  return ImageGenContext(
    mode: mode,
    style: style,
    paradigm: paradigm,
    characterName: characterName,
    characterDescription: characterDescription,
    lastMessage: (mode == ImageGenMode.customPrompt
        ? customPrompt
        : lastMessage),
    scenario: scenario,
    worldInfo: worldInfo,
    personaName: personaName,
    personaText: personaText,
    recentMessages: recentMessages,
    currentExpression: currentExpression,
    timeOfDay: timeOfDay,
    lightingHint: lightingHint,
    isGroupNonObserver: isGroupNonObserver,
    currentSpeakerId: currentSpeakerId,
    userInstruction: userInstruction,
  );
}
