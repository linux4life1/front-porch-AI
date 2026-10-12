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

part of '../home_page.dart';

/// Home right-click Manage Chats — same dialog as the in-chat folder menu.
extension _HomePageHistory on _HomePageState {
  Future<void> _showChatHistory({
    CharacterCard? character,
    GroupChat? group,
  }) async {
    if (!mounted) return;
    final chatService = Provider.of<ChatService>(context, listen: false);
    // 1:1 keys by imagePath basename / stableGroupId, never the dbId UUID.
    final ownerId = character != null
        ? _getCharacterIdFromCard(character)
        : 'group_${group!.id}';
    await showChatHistoryDialog(
      context: context,
      chatService: chatService,
      loadSessions: () => chatService.getSessionsForId(ownerId),
      startReplacement: false,
      closeOnDeleteCurrent: false,
      onNewChat: () => _startNewChatWith(character: character, group: group),
      onOpen: (sessionId) => _openHistorySession(
        sessionId: sessionId,
        character: character,
        group: group,
      ),
    );
  }

  Future<void> _openHistorySession({
    required String sessionId,
    CharacterCard? character,
    GroupChat? group,
  }) async {
    if (_openingChat || !mounted) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final groupRepo = group == null
          ? null
          : Provider.of<GroupChatRepository>(context, listen: false);
      chatService.beginSessionLoad();
      await _pushChatWhile(() async {
        try {
          if (character != null) {
            await chatService.setActiveCharacter(character);
          } else {
            await chatService.setActiveGroup(group!, groupRepo: groupRepo!);
          }
          await chatService.loadSession(sessionId);
        } finally {
          chatService.endSessionLoad();
        }
      }());
    } finally {
      _openingChat = false;
    }
  }
}
