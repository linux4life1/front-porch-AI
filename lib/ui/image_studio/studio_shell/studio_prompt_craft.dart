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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../image_studio.dart';

/// Resolve the live LLM for crafting: the launch snapshot goes stale when the
/// user switches backends mid-session, so re-query the provider each time and
/// fall back to the snapshot. Returns null when nothing is ready; with
/// [toast] that also shows the Craft button's static-quality notice.
LLMService? liveStudioLlm(
  BuildContext context,
  LLMService? launchLlm, {
  bool toast = false,
}) {
  final live = Provider.of<LLMProvider?>(context, listen: false)?.activeService;
  if (live?.isReady == true) return live;
  if (launchLlm != null && launchLlm.isReady) return launchLlm;
  if (toast) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'LLM not ready for smart crafting (using static quality)',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        backgroundColor: AppColors.surfaceContainerOf(context),
      ),
    );
  }
  return null;
}

/// One shared smart-prompt call for the Studio's "Write it for me" button and
/// the Expression-pack base prompt (the pack needs the same crafting when the
/// prompt box is empty). Thin delegation to
/// [ImageGenService.generateSmartPrompt], which owns the LLM-vs-static
/// fallback and never throws past its own ultimate fallback.
///
/// [characterName]/[characterDescription] are explicit: the Craft button
/// passes the launch character, while the pack flow passes the active subject
/// (e.g. a picked group member). [currentExpression] overrides the launch
/// snapshot's live emotion — the pack passes 'neutral' so the base prompt
/// carries no emotion tint for the per-slot modifier phrases to fight against.
Future<String> craftStudioImagePrompt(
  ImageStudio launch, {
  required ImageGenService service,
  required LLMService? llm,
  required ImageGenMode mode,
  required String style,
  String? characterName,
  String? characterDescription,
  String? currentExpression,
  String? userInstruction,
}) {
  return service.generateSmartPrompt(
    mode: mode,
    style: style,
    llmService: llm,
    customPrompt: launch.customPrompt,
    lastMessage: launch.lastMessage,
    characterName: characterName,
    characterDescription: characterDescription,
    characterPersonality: launch.characterPersonality,
    scenario: launch.scenario,
    worldInfo: launch.worldInfo,
    personaName: launch.personaName,
    personaText: launch.personaText,
    recentMessages: launch.recentMessages,
    currentExpression: currentExpression ?? launch.currentExpression,
    timeOfDay: launch.timeOfDay,
    lightingHint: launch.lightingHint,
    isGroupNonObserver: launch.isGroupNonObserver,
    currentSpeakerId: launch.currentSpeakerId,
    userInstruction: userInstruction,
  );
}

/// "Write it for me": craft from the prompt box with the live LLM. Shows the
/// static-quality notice and does nothing when no LLM is ready. [onStart],
/// [onCrafted] and [onFailed] are only called while [context] is mounted
/// (onStart synchronously, before the call).
Future<void> craftIntoPromptBox(
  BuildContext context,
  ImageStudio launch, {
  required ImageGenMode mode,
  required String style,
  required String box,
  required VoidCallback onStart,
  required ValueChanged<String> onCrafted,
  required ValueChanged<String> onFailed,
}) async {
  // Re-query the live LLM at craft time (the launch snapshot may be stale).
  final liveLlm = liveStudioLlm(context, launch.llmService, toast: true);
  if (liveLlm == null) return;
  onStart();
  try {
    final crafted = await craftStudioImagePrompt(
      launch,
      service: Provider.of<ImageGenService>(context, listen: false),
      llm: liveLlm,
      mode: mode,
      style: style,
      characterName: launch.characterName,
      characterDescription: launch.characterDescription,
      // Box content → guidance the LLM parses in (blank Freeform → scene).
      userInstruction: box.trim().isNotEmpty ? box.trim() : null,
    );
    if (context.mounted) onCrafted(crafted);
  } catch (e) {
    if (context.mounted) {
      onFailed(
        'Craft failed: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
      );
    }
  }
}

/// The Expression pack's base prompt for [card]: crafted neutral (no emotion
/// tint) as a character portrait, with whatever LLM is live (no toast).
Future<String> craftPackBasePrompt(
  BuildContext context,
  ImageStudio launch,
  CharacterCard card,
  String? instruction, {
  required String style,
}) => craftStudioImagePrompt(
  launch,
  service: context.read<ImageGenService>(),
  llm: liveStudioLlm(context, launch.llmService),
  mode: ImageGenMode.characterPortrait,
  style: style,
  characterName: card.name,
  characterDescription: card.description,
  currentExpression: 'neutral',
  userInstruction: instruction,
);
