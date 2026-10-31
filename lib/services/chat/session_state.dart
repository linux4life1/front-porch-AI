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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';

/// The open chat every ChatService domain reads: its messages, its session
/// id, the 1:1 character and the group manager. ChatService owns one and
/// hands the same instance to every leaf, so all of them see one chat.
///
/// Not a notifier: ChatService still notifies after it changes this.
class ChatSessionState {
  ChatSessionState({void Function(String id)? onChatOpened})
    : _onChatOpened = onChatOpened;

  final void Function(String id)? _onChatOpened;

  /// The chat's in-memory message list. One list for the life of the
  /// service: chat switches clear and refill it, never replace it.
  final List<ChatMessage> messages = [];

  /// The 1:1 character, or the group speaker the Realism dance is
  /// impersonating for the length of a group turn.
  CharacterCard? activeCharacter;

  GroupTurnManager? groupManager;

  String? _currentSessionId;

  /// The chat open now. Every change goes through here, so KoboldCpp's saved
  /// cache follows it: the chat left is let go unless Settings keeps recent
  /// chats ready. A switch passes through no chat (null) on its way; only
  /// the chat it lands on is told.
  String? get currentSessionId => _currentSessionId;
  set currentSessionId(String? id) {
    if (id == _currentSessionId) return;
    _currentSessionId = id;
    if (id != null) _onChatOpened?.call(id);
  }

  GroupChat? get activeGroup => groupManager?.activeGroup;

  List<CharacterCard> get groupCharacters =>
      groupManager?.characters ?? const <CharacterCard>[];
}
