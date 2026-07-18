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

// The Studio's prompt-crafting helpers, extracted from the coordinator to
// keep image_studio.dart under the 500-line cap. A `part` (not a separate
// library) because these read a dozen ImageStudio launch fields directly —
// an interface or param pass-through would re-inflate the coordinator.
part of 'image_studio.dart';

/// Resolve the live LLM for crafting: the launch snapshot goes stale when the
/// user switches backends mid-session, so re-query the provider each time and
/// fall back to the snapshot. Returns null when nothing is ready; with
/// [toast] that also shows the Craft button's static-quality notice.
LLMService? _liveStudioLlm(
  BuildContext context,
  LLMService? launchLlm, {
  bool toast = false,
}) {
  final live = Provider.of<LLMProvider>(context, listen: false).activeService;
  if (live.isReady) return live;
  if (launchLlm != null && launchLlm.isReady) return launchLlm;
  if (toast) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'LLM not ready for smart crafting (using static quality)',
        ),
        backgroundColor: AppColors.surfaceContainerOf(context),
      ),
    );
  }
  return null;
}

/// Build a fresh [ImageGenContext] snapshot for a Studio subject. The
/// character name/description are explicit because the coordinator substitutes
/// the *active* subject (a picked group member, the whole cast, or the 1:1
/// character); everything else mirrors the launch context verbatim.
ImageGenContext _buildStudioContext(
  ImageStudio widget, {
  required ImageGenMode mode,
  required String style,
  required String paradigm,
  String? characterName,
  String? characterDescription,
}) {
  return ImageGenContext(
    mode: mode,
    style: style,
    paradigm: paradigm,
    characterName: characterName,
    characterDescription: characterDescription,
    lastMessage: mode == ImageGenMode.customPrompt
        ? widget.customPrompt
        : widget.lastMessage,
    scenario: widget.scenario,
    worldInfo: widget.worldInfo,
    personaName: widget.personaName,
    personaText: widget.personaText,
    recentMessages: widget.recentMessages,
    currentExpression: widget.currentExpression,
    timeOfDay: widget.timeOfDay,
    lightingHint: widget.lightingHint,
    isGroupNonObserver: widget.isGroupNonObserver,
    currentSpeakerId: widget.currentSpeakerId,
  );
}

/// One shared smart-prompt call for the Studio's "Write it for me" button and
/// the Expression-pack base prompt (the pack needs the same crafting when the
/// prompt box is empty). Thin delegation to
/// [ImageGenService.generateSmartPrompt], which owns the LLM-vs-static
/// fallback and never throws past its own ultimate fallback.
///
/// [characterName]/[characterDescription] are explicit for the same reason as
/// [_buildStudioContext]: the Craft button passes the launch character, while
/// the pack flow passes the active subject (e.g. a picked group member).
/// [currentExpression] overrides the launch snapshot's live emotion — the
/// pack passes 'neutral' so the base prompt carries no emotion tint for the
/// per-slot modifier phrases to fight against.
Future<String> _craftStudioPrompt(
  ImageStudio widget, {
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
    customPrompt: widget.customPrompt,
    lastMessage: widget.lastMessage,
    characterName: characterName,
    characterDescription: characterDescription,
    characterPersonality: widget.characterPersonality,
    scenario: widget.scenario,
    worldInfo: widget.worldInfo,
    personaName: widget.personaName,
    personaText: widget.personaText,
    recentMessages: widget.recentMessages,
    currentExpression: currentExpression ?? widget.currentExpression,
    timeOfDay: widget.timeOfDay,
    lightingHint: widget.lightingHint,
    isGroupNonObserver: widget.isGroupNonObserver,
    currentSpeakerId: widget.currentSpeakerId,
    userInstruction: userInstruction,
  );
}
