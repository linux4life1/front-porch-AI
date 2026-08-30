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
//
// Speaker and cover resolution for ChatPage: focused participant, character
// image path, bubble speaker (avatar + name color), and star-aware cover.
// Extracted verbatim from chat_page.dart (god-file campaign) —
// part of the same library, so every private member is still in scope.

part of 'chat_page.dart';

extension _ChatPageSpeakers on _ChatPageState {
  /// Resolve the currently-focused participant from the unified cast, defaulting
  /// to the first participant (the host in a 1:1/NPC chat). Returns null only
  /// when no chat is loaded.
  ChatParticipant? _focusedParticipant(ChatService chat) {
    final cast = chat.cast;
    if (cast.isEmpty) return null;
    if (_focusedParticipantId != null) {
      for (final p in cast) {
        if (p.id == _focusedParticipantId) return p;
      }
    }
    return cast.first;
  }

  /// Resolve a character [imagePath] (basename or full path) to a [File].
  /// Always use this instead of [File(imagePath)] directly.
  File _resolveCharImage(String imagePath) {
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(imagePath);
  }

  /// Resolve the avatar + name color for a message's speaker from the unified
  /// [ChatService.cast], replacing the old group-vs-1:1/guest branches with one
  /// path. A non-host participant (group member or Scene Guest) gets its own
  /// avatar and a palette color keyed by its order among non-host speakers
  /// (preserving the previous per-mode coloring). The host gets its avatar and
  /// no color; an unresolved sender (a departed guest) gets the placeholder.
  (File?, Color?) _resolveSpeaker(ChatService chatService, ChatMessage msg) {
    if (msg.isUser) return (null, null);
    final cast = chatService.cast;
    final nonHost = cast.where((p) => !p.isHost).toList();

    ChatParticipant? speaker;
    final stamped = msg.characterId;
    if (stamped != null && stamped.isNotEmpty) {
      for (final p in cast) {
        if (p.id == stamped) {
          speaker = p;
          break;
        }
      }
    }
    if (speaker == null) {
      final byName = cast.where((p) => p.name == msg.sender).toList();
      if (byName.length == 1) speaker = byName.first;
    }

    if (speaker != null && !speaker.isHost) {
      final img = _coverFor(chatService, speaker.card);
      final idx = nonHost.indexWhere((p) => p.id == speaker!.id);
      return (img, _ChatPageState._groupCharacterColor(idx >= 0 ? idx : 0));
    }

    // Host message (or an unresolved/departed sender). Use the host avatar only
    // for an actual host message; an unknown non-host sender gets the
    // placeholder rather than the host's face under someone else's name.
    final host = cast.where((p) => p.isHost).firstOrNull;
    final isHostMsg =
        (speaker != null && speaker.isHost) ||
        (host != null &&
            (msg.sender == host.name ||
                (msg.characterId != null && msg.characterId == host.id)));
    final img = (isHostMsg && host != null)
        ? _coverFor(chatService, host.card)
        : null;
    return (img, null);
  }

  /// Star-aware avatar for a character chip (header, bubbles, pickers): the
  /// ★ gallery cover of the ORIGIN library card — the SAME face the home
  /// grid, web library, and exports show ("one face per character",
  /// maintainer 2026-07-16) — else the portrait. Null when imageless.
  File? _coverFor(ChatService chat, CharacterCard card) {
    final lib = chat.originLibraryCardFor(card) ?? card;
    final cover = Provider.of<CharacterRepository>(
      context,
      listen: false,
    ).coverImageFileFor(lib);
    if (cover != null) return cover;
    final path = lib.imagePath ?? card.imagePath;
    return path == null ? null : _resolveCharImage(path);
  }
}
