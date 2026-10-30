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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// One Chat Colors row of the UI Settings dialog, in display order. Each
/// slot knows where its color lives in the three stores it can be read from
/// or written to: the session theme overrides, the per-character extension,
/// and the global [StorageService] preference.
enum ChatColorSlot {
  userBubble('User Bubble'),
  userText('User Text'),
  aiBubble('AI Bubble'),
  aiText('AI Text'),
  dialogue('Dialogue (Quoted)'),
  action('Actions (*text*)');

  const ChatColorSlot(this.label);

  final String label;

  Color? themeColor(ChatThemeOverrides o, ChatThemePreset preset) =>
      switch (this) {
        userBubble => o.resolvedUserBubbleColor(preset),
        userText => o.resolvedUserTextColor(preset),
        aiBubble => o.resolvedAiBubbleColor(preset),
        aiText => o.resolvedAiTextColor(preset),
        dialogue => o.resolvedDialogueColor(preset),
        action => o.resolvedActionColor(preset),
      };

  Color globalColor(StorageService storage) => switch (this) {
    userBubble => storage.uiSettings.globalUserBubbleColor,
    userText => storage.uiSettings.globalUserTextColor,
    aiBubble => storage.uiSettings.globalAiBubbleColor,
    aiText => storage.uiSettings.globalAiTextColor,
    dialogue => storage.uiSettings.globalDialogueColor,
    action => storage.uiSettings.globalActionColor,
  };

  Color? characterColor(FrontPorchExtensions? e) => switch (this) {
    userBubble => e?.userBubbleColor,
    userText => e?.userTextColor,
    aiBubble => e?.aiBubbleColor,
    aiText => e?.aiTextColor,
    dialogue => e?.dialogueColor,
    action => e?.actionColor,
  };

  void writeTheme(ChatThemeOverrides o, String hex) {
    switch (this) {
      case userBubble:
        o.userBubbleColor = hex;
      case userText:
        o.userTextColor = hex;
      case aiBubble:
        o.aiBubbleColor = hex;
      case aiText:
        o.aiTextColor = hex;
      case dialogue:
        o.dialogueColor = hex;
      case action:
        o.actionColor = hex;
    }
  }

  FrontPorchExtensions writeCharacter(FrontPorchExtensions e, Color c) =>
      switch (this) {
        userBubble => e.copyWith(userBubbleColor: c),
        userText => e.copyWith(userTextColor: c),
        aiBubble => e.copyWith(aiBubbleColor: c),
        aiText => e.copyWith(aiTextColor: c),
        dialogue => e.copyWith(dialogueColor: c),
        action => e.copyWith(actionColor: c),
      };

  Future<void> writeGlobal(StorageService storage, Color c) => switch (this) {
    userBubble => storage.uiSettings.setGlobalUserBubbleColor(c),
    userText => storage.uiSettings.setGlobalUserTextColor(c),
    aiBubble => storage.uiSettings.setGlobalAiBubbleColor(c),
    aiText => storage.uiSettings.setGlobalAiTextColor(c),
    dialogue => storage.uiSettings.setGlobalDialogueColor(c),
    action => storage.uiSettings.setGlobalActionColor(c),
  };
}

/// `RRGGBB` (alpha dropped, upper case) — the form theme overrides store.
String chatColorToHex(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

/// Copies [character] with [extensions] swapped in (same `dbId`), so the
/// repository update replaces the card rather than mutating the live one.
CharacterCard cloneCharacterWithExtensions(
  CharacterCard character,
  FrontPorchExtensions extensions,
) {
  final updated = CharacterCard(
    name: character.name,
    description: character.description,
    personality: character.personality,
    scenario: character.scenario,
    firstMessage: character.firstMessage,
    mesExample: character.mesExample,
    systemPrompt: character.systemPrompt,
    postHistoryInstructions: character.postHistoryInstructions,
    alternateGreetings: List.from(character.alternateGreetings),
    tags: List.from(character.tags),
    imagePath: character.imagePath,
    folderId: character.folderId,
    lorebook: character.lorebook != null
        ? Lorebook(entries: List.from(character.lorebook!.entries))
        : null,
    worldNames: List.from(character.worldNames),
    loreWorldNames: character.loreWorldNames == null
        ? null
        : List.from(character.loreWorldNames!),
    ttsVoice: character.ttsVoice,
    frontPorchExtensions: extensions,
    rawExtensions: character.rawExtensions != null
        ? Map<String, dynamic>.from(character.rawExtensions!)
        : null,
    avatarImages: character.avatarImages != null
        ? List.from(character.avatarImages!)
        : null,
  )..dbId = character.dbId;
  // The roster keeps showing the same default face after the swap.
  updated.primeAvatarIndex = character.primeAvatarIndex;
  return updated;
}

/// Applies [mutate] to [character]'s extensions, saves the clone through
/// [persist], and returns it for the caller to show.
Future<CharacterCard> saveCharacterExtension(
  Future<void> Function(CharacterCard) persist,
  CharacterCard character,
  FrontPorchExtensions Function(FrontPorchExtensions) mutate,
) async {
  final currentExtensions =
      character.frontPorchExtensions ?? FrontPorchExtensions();
  final updatedExtensions = mutate(currentExtensions);
  updatedExtensions.ensureStableId();
  final updatedCharacter = cloneCharacterWithExtensions(
    character,
    updatedExtensions,
  );
  await persist(updatedCharacter);
  return updatedCharacter;
}
