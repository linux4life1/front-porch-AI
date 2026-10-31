// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/image_command_service.dart';
import 'package:front_porch_ai/services/chat/session_state.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// The scene an `/image` prompt is written from, and the writing itself.
///
/// Context assembly here intentionally mirrors the Image Studio launch site
/// (`chat_page._showImageGenDialog`) so a slash-command generation and a
/// studio generation see the same scene; keep the two collection blocks in
/// sync. Raw message text is passed as-is: `ImagePromptBuilder` owns
/// think-block stripping and narrative cleaning.
///
/// Parity: 1:1 and group chats share this one path. The only branch is
/// speaker resolution (active character vs. most recent non-user sender /
/// named member), exactly like the studio launch site. No Realism or Needs
/// work happens here.
class ImagePromptCrafter {
  ImagePromptCrafter({
    required ChatSessionState session,
    required StorageService storage,
    required UserPersonaService personas,
    required WorldRepository worlds,
    required LLMService? Function() llm,
    required List<CharacterCard> Function() guestCards,
    required String? Function() expressionLabel,
    required String Function() timeOfDay,
  }) : _session = session,
       _storage = storage,
       _personas = personas,
       _worlds = worlds,
       _llm = llm,
       _guestCards = guestCards,
       _expressionLabel = expressionLabel,
       _timeOfDay = timeOfDay;

  final ChatSessionState _session;
  final StorageService _storage;
  final UserPersonaService _personas;
  final WorldRepository _worlds;
  final LLMService? Function() _llm;
  final List<CharacterCard> Function() _guestCards;
  final String? Function() _expressionLabel;
  final String Function() _timeOfDay;

  /// The character a `/image` request is about: an explicitly named group
  /// member/guest wins, then the most recent non-user speaker (group), then
  /// the active 1:1 character.
  CharacterCard? speakerFor(ImageCommandRequest request) {
    final groupCharacters = _session.groupCharacters;
    final candidates = <CharacterCard>[
      ?_session.activeCharacter,
      ...groupCharacters,
      ..._guestCards(),
    ];
    final wanted = request.kind == ImageCommandKind.character
        ? request.text.trim().toLowerCase()
        : '';
    if (wanted.isNotEmpty) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == wanted) return c;
      }
      final partial = candidates
          .where((c) => c.name.toLowerCase().contains(wanted))
          .toList();
      if (partial.length == 1) return partial.first;
    }
    // Most recent AI speaker (matters in groups; in a 1:1 this resolves to
    // the active character anyway).
    final userName = _personas.persona.name;
    for (final m in _session.messages.reversed) {
      if (m.isUser || m.sender == 'System' || m.sender == userName) continue;
      for (final c in candidates) {
        if (c.name == m.sender) return c;
      }
    }
    return _session.activeCharacter ??
        (groupCharacters.isNotEmpty ? groupCharacters.first : null);
  }

  /// Assemble the live chat context and craft the image prompt through
  /// `ImageGenService.generateSmartPrompt` (LLM when ready, static fallback
  /// otherwise).
  ///
  /// The Image Studio's "Write it for me" passes what the person typed as
  /// [instruction], for the builder to parse into the prompt.
  Future<String?> craft(
    ImageGenService igs,
    ImageCommandRequest request, {
    String? instruction,
  }) {
    // scene → customPrompt with no typed text: the builder distills the current
    // scene from the recent narrative (the former "Visualize Scene" mode). custom
    // → customPrompt with the user's free description. raw never reaches craft.
    final mode = switch (request.kind) {
      ImageCommandKind.me => ImageGenMode.userAvatar,
      ImageCommandKind.character => ImageGenMode.characterPortrait,
      _ => ImageGenMode.customPrompt,
    };
    final character = speakerFor(request);
    final userName = _personas.persona.name;

    String? lastMessage;
    final recentMessages = <String>[];
    for (final m in _session.messages.reversed) {
      if (recentMessages.length >= 12) break;
      final txt = m.displayText;
      if (txt.isEmpty) continue;
      recentMessages.insert(0, txt);
      if (lastMessage == null && !m.isUser && m.sender != 'System') {
        lastMessage = txt;
      }
    }
    lastMessage ??= recentMessages.isNotEmpty ? recentMessages.last : null;

    String? worldInfo;
    final worlds = _worlds.worlds;
    if (worlds.isNotEmpty) worldInfo = worlds.first.description;

    final llm = _llm();
    final isGroupNonObserver = _session.groupManager?.isActive ?? false;

    // `/image last` distills just the single most recent turn; `/image [scene]`
    // distills the recent run (the builder caps how many it actually uses).
    final effectiveRecent =
        (request.kind == ImageCommandKind.scene && request.text == 'last')
        ? (lastMessage != null ? <String>[lastMessage] : const <String>[])
        : recentMessages;

    return igs.generateSmartPrompt(
      mode: mode,
      style: _storage.imageGenSettings.imageGenStyle,
      llmService: (llm != null && llm.isReady) ? llm : null,
      customPrompt: request.kind == ImageCommandKind.custom
          ? request.text
          : null,
      lastMessage: lastMessage,
      characterName: character?.name,
      characterDescription: character?.description,
      scenario: character?.scenario,
      worldInfo: worldInfo,
      personaName: userName,
      personaText: _personas.persona.persona,
      recentMessages: effectiveRecent,
      currentExpression: _expressionLabel(),
      timeOfDay: _timeOfDay(),
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: isGroupNonObserver ? character?.name : null,
      userInstruction: instruction,
    );
  }
}
