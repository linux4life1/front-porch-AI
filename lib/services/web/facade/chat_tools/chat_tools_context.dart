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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// What every chat-tools collaborator shares: the live chat, storage, the
/// broadcast hook, and the focus rules the sidebar sections agree on.
class ChatToolsContext {
  ChatToolsContext(this.chat, this.storage, this._hub);

  final ChatService chat;
  final StorageService storage;
  final StreamHub? _hub;

  void notify() => _hub?.broadcastChatUpdate();

  /// The focused cast participant, or null when none/unknown.
  ChatParticipant? focusedParticipant(String? id) {
    if (id == null) return null;
    for (final p in chat.cast) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// A focused Scene Guest (1:1 non-host cast entry). Guests carry NO pockets
  /// record — but the 1:1 record accessors ignore the character id (there is
  /// only `_pockets`, the host's), so a guest-focused pocket surface would
  /// silently read AND WRITE the host's kit under the guest's name (hostile
  /// self-review, 2026-08-13; the ✕ had the same hole). In a group every
  /// participant is a real member, so this is 1:1-only by construction.
  bool isGuestFocus(ChatParticipant? focused) =>
      focused != null && !focused.isHost && !chat.isGroupMode;

  /// The growth owner behind [participantId]: the focused participant, or the
  /// host (1:1) / first member as fallback — mirrors the desktop's focused
  /// default.
  ChatParticipant? growthOwner(String? participantId) {
    final focused = focusedParticipant(participantId);
    if (focused != null) return focused;
    for (final p in chat.cast) {
      if (p.isHost) return p;
    }
    return chat.cast.firstOrNull;
  }
}
