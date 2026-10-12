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
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/home/dialogs/session_picker_dialog.dart';
import 'package:front_porch_ai/ui/pages/home/open_chat_env.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Every way Home enters a chat: card taps, "Start New Chat", Manage Chats,
/// and the `OPEN_CHAT` launch hook. Owns the busy guard that blocks stacked
/// open-chat taps while setActiveCharacter / loadSession runs (can take
/// seconds). Without it, multi-tap after exit→reenter races dispose and
/// throws "State no longer has a context".
///
/// [context] is the Home State's own element, captured once, and [isMounted]
/// is State.mounted — NOT a fresh State.context read. Reading State.context
/// after unmount throws before .mounted is ever evaluated (exit chat →
/// reenter multi-tap race, maintainer 2026-08-11).
class HomeChatOpener {
  HomeChatOpener({
    required this.context,
    required this.isMounted,
    required this.onChatClosed,
  });

  final BuildContext context;
  final bool Function() isMounted;

  /// Runs after the pushed ChatPage pops (the activity cache refresh).
  final VoidCallback onChatClosed;

  bool _openingChat = false;

  /// `--dart-define=OPEN_CHAT=Flora` opens that 1:1 card once per process.
  /// Empty define is a no-op. Static so a Home remount cannot re-fire.
  static bool _openChatEnvConsumed = false;

  /// Push ChatPage immediately and drain [load] after pop. The session
  /// overlay covers hydrate — awaiting load first is the home-grid freeze.
  /// A failed load pops the ghost ChatPage and snacks the error.
  Future<void> _pushChatWhile(Future<void> load) async {
    if (!isMounted()) {
      await load;
      return;
    }
    final nav = Navigator.of(context);
    final route = nav.push(MaterialPageRoute(builder: (_) => const ChatPage()));
    try {
      await load;
    } catch (e, st) {
      debugPrint('[Home] open chat failed: $e\n$st');
      if (isMounted() && nav.canPop()) {
        nav.pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
      }
      return;
    }
    await route;
    if (isMounted()) onChatClosed();
  }

  /// Launch hook: after Home's first frame (and again when the library
  /// finishes loading), open the 1:1 card named by [OpenChatEnv.name].
  /// Empty define is a no-op. Groups are never considered. Multiple
  /// sessions skip the picker and load the most recent — no new chat,
  /// no message, no Save, no Edit Details.
  void maybeOpenChatFromEnv() {
    if (_openChatEnvConsumed || !isMounted()) return;
    if (!OpenChatEnv.enabled) {
      _openChatEnvConsumed = true;
      return;
    }
    late final CharacterRepository repo;
    try {
      repo = Provider.of<CharacterRepository>(context, listen: false);
    } catch (_) {
      return;
    }
    if (repo.isLoading) return;
    final character = OpenChatEnv.findOneToOneCard(
      repo.characters,
      name: OpenChatEnv.name,
    );
    if (character == null) {
      // Empty library usually means load has not landed yet — wait for
      // the characters listener rather than consuming the hook.
      if (repo.characters.isEmpty) return;
      _openChatEnvConsumed = true;
      debugPrint(
        '[Home] OPEN_CHAT=${OpenChatEnv.name}: no 1:1 CharacterCard '
        'with that exact name',
      );
      return;
    }
    _openChatEnvConsumed = true;
    _openChatSkippingPicker(character);
  }

  /// Same open path as [tapCharacter], but skip the session picker and
  /// never start a new chat.
  Future<void> _openChatSkippingPicker(CharacterCard character) async {
    if (_openingChat || !isMounted()) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      if (!await chatService.hasMultipleSavedSessions(character)) {
        await _pushChatWhile(chatService.setActiveCharacter(character));
        return;
      }
      final charId = character.stableGroupId;
      final sessions = await chatService.getSessionsForId(charId);
      if (!isMounted()) return;
      final selectedId = OpenChatEnv.mostRecentSessionId(sessions);
      if (selectedId != null && sessions.length > 1) {
        chatService.beginSessionLoad();
        await _pushChatWhile(() async {
          try {
            await chatService.setActiveCharacter(character);
            await chatService.loadSession(selectedId);
          } finally {
            chatService.endSessionLoad();
          }
        }());
      } else {
        await _pushChatWhile(chatService.setActiveCharacter(character));
      }
    } finally {
      _openingChat = false;
    }
  }

  Future<void> tapCharacter(CharacterCard character) async {
    if (_openingChat || !isMounted()) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      // One session (the common case): skip the full session list + the
      // getAllCharacters scan inside getSessionsForId. The picker still
      // uses the basename id when there are several chats.
      if (!await chatService.hasMultipleSavedSessions(character)) {
        await _pushChatWhile(chatService.setActiveCharacter(character));
        return;
      }
      // getSessionsForId resolves 1:1 ids by imagePath basename (stableGroupId)
      // — the dbId UUID silently returns [] and kills the session picker
      // (documented identity gotcha; same warning at enhance_wizard_page.dart).
      final charId = character.stableGroupId;
      final sessions = await chatService.getSessionsForId(charId);

      if (!isMounted()) return;

      if (sessions.length > 1) {
        final selectedId = await showSessionPickerDialog(
          context,
          sessions,
          character.name,
        );
        if (selectedId == null || !isMounted()) return;
        chatService.beginSessionLoad();
        await _pushChatWhile(() async {
          try {
            await chatService.setActiveCharacter(character);
            if (selectedId != '__new__') {
              await chatService.loadSession(selectedId);
            } else {
              await chatService.startNewChat();
            }
          } finally {
            chatService.endSessionLoad();
          }
        }());
      } else {
        await _pushChatWhile(chatService.setActiveCharacter(character));
      }
    } finally {
      _openingChat = false;
    }
  }

  Future<void> tapGroup(GroupChat group) async {
    if (_openingChat || !isMounted()) return;
    _openingChat = true;
    try {
      final chatService = Provider.of<ChatService>(context, listen: false);
      final groupRepo = Provider.of<GroupChatRepository>(
        context,
        listen: false,
      );
      final groupId = 'group_${group.id}';
      final sessions = await chatService.getSessionsForId(groupId);

      if (!isMounted()) return;

      if (sessions.length > 1) {
        final selectedId = await showSessionPickerDialog(
          context,
          sessions,
          group.name,
        );
        if (selectedId == null || !isMounted()) return;
        chatService.beginSessionLoad();
        await _pushChatWhile(() async {
          try {
            await chatService.setActiveGroup(group, groupRepo: groupRepo);
            if (selectedId != '__new__') {
              await chatService.loadSession(selectedId);
            } else {
              await chatService.startNewChat();
            }
          } finally {
            chatService.endSessionLoad();
          }
        }());
      } else {
        await _pushChatWhile(
          chatService.setActiveGroup(group, groupRepo: groupRepo),
        );
      }
    } finally {
      _openingChat = false;
    }
  }

  /// "Start New Chat" from either card's context menu: ask which persona
  /// (step 2 — never assumed), then open a fresh session and enter it.
  /// Cancelling the picker starts nothing. One handler for characters and
  /// group casts; [ChatService.startFreshChatWith] owns the ordering.
  Future<void> startNewChatWith({
    CharacterCard? character,
    GroupChat? group,
  }) async {
    if (_openingChat || !isMounted()) return;
    _openingChat = true;
    try {
      final subject = character?.name ?? group?.name ?? '';
      final personaId = await showPersonaPickerDialog(
        context,
        subject: subject,
      );
      if (personaId == null || !isMounted()) return;

      final chatService = Provider.of<ChatService>(context, listen: false);
      await _pushChatWhile(
        chatService.startFreshChatWith(
          character: character,
          group: group,
          groupRepo: group == null
              ? null
              : Provider.of<GroupChatRepository>(context, listen: false),
          personaId: personaId,
        ),
      );
    } finally {
      _openingChat = false;
    }
  }

  /// Home right-click Manage Chats — same dialog as the in-chat folder menu.
  Future<void> showChatHistory({
    CharacterCard? character,
    GroupChat? group,
  }) async {
    if (!isMounted()) return;
    final chatService = Provider.of<ChatService>(context, listen: false);
    // 1:1 keys by imagePath basename / stableGroupId, never the dbId UUID.
    final ownerId = character != null
        ? character.stableGroupId
        : 'group_${group!.id}';
    await showChatHistoryDialog(
      context: context,
      chatService: chatService,
      loadSessions: () => chatService.getSessionsForId(ownerId),
      startReplacement: false,
      closeOnDeleteCurrent: false,
      onNewChat: () => startNewChatWith(character: character, group: group),
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
    if (_openingChat || !isMounted()) return;
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
