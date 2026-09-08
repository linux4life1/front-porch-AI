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

part of 'ui_settings_dialog.dart';

/// Dual-routed persistence helpers for [UiSettingsDialog]'s Chat Colors rows
/// and avatar-lock toggle: when a session theme is active, writes go to
/// [ChatService.sessionThemeOverrides] (or the bound Waifu overrides when
/// [UiSettingsDialog.onThemeOverrides] is set); otherwise they go to the
/// per-character extension (if a character is open) or the global
/// [StorageService] preference. Extracted verbatim from UiSettingsDialog;
/// the two `setState` call sites now go through the shell's `rebuildState`
/// bridge because extensions can't call a State's protected members directly.
extension _UiSettingsUpdatesSection on _UiSettingsDialogState {
  /// When a theme is active, writes go to session theme overrides.
  /// When no theme, writes go to per-character extensions or global prefs.
  bool _hasActiveTheme(ChatService chatService) =>
      _themeOf(chatService).hasTheme;

  Future<void> _updateUserBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.userBubbleColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(userBubbleColor: color),
      );
    } else {
      await storage.setGlobalUserBubbleColor(color);
    }
  }

  Future<void> _updateUserTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.userTextColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(userTextColor: color),
      );
    } else {
      await storage.setGlobalUserTextColor(color);
    }
  }

  Future<void> _updateAiBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.aiBubbleColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(aiBubbleColor: color),
      );
    } else {
      await storage.setGlobalAiBubbleColor(color);
    }
  }

  Future<void> _updateAiTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.aiTextColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(aiTextColor: color),
      );
    } else {
      await storage.setGlobalAiTextColor(color);
    }
  }

  Future<void> _updateDialogueColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.dialogueColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(dialogueColor: color),
      );
    } else {
      await storage.setGlobalDialogueColor(color);
    }
  }

  Future<void> _updateActionColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    if (_hasActiveTheme(chatService)) {
      final o = _themeOf(chatService);
      o.actionColor = _colorToHex(color);
      _commitTheme(chatService, o);
      return;
    }
    final character = _characterNotifier.value;
    if (character != null) {
      await _updateCharacterExtension(
        context,
        (e) => e.copyWith(actionColor: color),
      );
    } else {
      await storage.setGlobalActionColor(color);
    }
  }

  Future<void> _updateAvatarLocked(BuildContext context, bool locked) async {
    final character = _characterNotifier.value;
    if (character == null) return;

    final currentExtensions =
        character.frontPorchExtensions ?? FrontPorchExtensions();
    final updatedExtensions = currentExtensions.copyWith(avatarLocked: locked);
    updatedExtensions.ensureStableId();
    final updatedCharacter = _cloneCharacter(character, updatedExtensions);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    await charRepo.updateCharacter(updatedCharacter);
    rebuildState(() {
      _characterNotifier.value = updatedCharacter;
    });
  }

  Future<void> _updateCharacterExtension(
    BuildContext context,
    FrontPorchExtensions Function(FrontPorchExtensions) mutate,
  ) async {
    final character = _characterNotifier.value;
    if (character == null) return;
    final currentExtensions =
        character.frontPorchExtensions ?? FrontPorchExtensions();
    final updatedExtensions = mutate(currentExtensions);
    updatedExtensions.ensureStableId();
    final updatedCharacter = _cloneCharacter(character, updatedExtensions);
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    await charRepo.updateCharacter(updatedCharacter);
    rebuildState(() {
      _characterNotifier.value = updatedCharacter;
    });
  }

  CharacterCard _cloneCharacter(
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
      ttsVoice: character.ttsVoice,
      frontPorchExtensions: extensions,
      rawExtensions: character.rawExtensions != null
          ? Map<String, dynamic>.from(character.rawExtensions!)
          : null,
      avatarImages: character.avatarImages != null
          ? List.from(character.avatarImages!)
          : null,
    )..dbId = character.dbId;
    return updated;
  }

  String _colorToHex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
}
