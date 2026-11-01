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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_deps.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

/// Whose memories a turn retrieves: the RAG source character ids and the
/// session-scoped set (see [sourceIds]). Body as the generation part held
/// it; zero behaviour change.
class RagSources {
  RagSources(this._d);

  final PromptDeps _d;

  ChatSessionState get _session => _d.session;
  AppDatabase get _db => _d.services.db();
  CharacterRepository? get _characterRepository => _d.services.characters();
  GroupChatRepository? get _groupChatRepository =>
      _d.doors.entry().groupRepository;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  String _getCharacterIdFromCard(CharacterCard c) => _session.characterIdFor(c);
  String _getCharacterId() => _session.ragCharacterId();

  /// Resolve the RAG source character ids for retrieval.
  ///
  /// Normally keyed on the active character (or the group bucket). When a
  /// [guest] is supplied (Scene Guests Phase 4), retrieval is keyed on the
  /// guest's OWN id instead — the same id the guest embeds under via
  /// `_maybeEmbedMessages` — plus that guest's cross-character memory sources.
  /// This keeps the guest's episodic memory isolated from the host's: the
  /// host's memories are never injected on a guest turn, and vice versa.
  ///
  /// Groups: conversation RAG stays on `group_<id>`. Data Bank rows and
  /// library `memory_sources` key by the origin portrait basename / library
  /// UUID, never the group-private avatar UUID. [sessionScoped] is the
  /// group bucket plus those library ids so 1:1 embeddings cannot bleed;
  /// explicit cross-character sources that are not members stay unscoped.
  Future<({List<String> sourceIds, Set<String> sessionScoped})> sourceIds({
    CharacterCard? guest,
  }) async {
    final currentId = guest != null
        ? _getCharacterIdFromCard(guest)
        : _getCharacterId();
    final sourceIds = <String>[currentId];
    final sessionScoped = <String>{if (currentId.isNotEmpty) currentId};

    Future<void> addMemorySources(String? libraryDbId) async {
      if (libraryDbId == null || libraryDbId.isEmpty) return;
      try {
        final dbChar = await _db.getCharacterById(libraryDbId);
        final ms = dbChar.memorySources;
        if (ms.isNotEmpty && ms != '[]') {
          final decoded = List<String>.from(
            (jsonDecode(ms) as List).map((e) => e.toString()),
          );
          for (final id in decoded) {
            if (!sourceIds.contains(id)) sourceIds.add(id);
          }
          if (decoded.isNotEmpty) {
            debugPrint('[RAG:Chat] Cross-character sources: $decoded');
          }
        }
      } catch (e) {
        debugPrint('[RAG:Chat] Failed to read memorySources: $e');
      }
    }

    if (guest != null) {
      await addMemorySources(guest.dbId);
      return (sourceIds: sourceIds, sessionScoped: sessionScoped);
    }

    if (_activeGroup != null) {
      final library =
          _characterRepository?.characters ?? const <CharacterCard>[];
      final repo = _groupChatRepository;
      final members = repo != null
          ? await repo.getMembersForGroup(_activeGroup!.id)
          : const <GroupMember>[];
      if (members.isNotEmpty) {
        for (final m in members) {
          final ident = MemberOriginResolver.libraryRagIdentity(
            originStableId: m.originStableId,
            originLibraryDbId: m.originLibraryDbId,
            memberName: m.name,
            libraryCharacters: library,
          );
          final sid = ident.sourceId;
          if (sid != null && sid.isNotEmpty) {
            if (!sourceIds.contains(sid)) sourceIds.add(sid);
            sessionScoped.add(sid);
          }
          await addMemorySources(ident.libraryDbId);
        }
      } else {
        for (final c in _groupCharacters) {
          final ident = MemberOriginResolver.libraryRagIdentity(
            originStableId: null,
            originLibraryDbId: null,
            memberName: c.name,
            libraryCharacters: library,
          );
          final sid = ident.sourceId;
          if (sid != null && sid.isNotEmpty) {
            if (!sourceIds.contains(sid)) sourceIds.add(sid);
            sessionScoped.add(sid);
          }
          await addMemorySources(ident.libraryDbId);
        }
      }
      return (sourceIds: sourceIds, sessionScoped: sessionScoped);
    }

    await addMemorySources(_session.activeCharacter?.dbId);
    return (sourceIds: sourceIds, sessionScoped: sessionScoped);
  }
}
