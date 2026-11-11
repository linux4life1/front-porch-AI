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
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_deps.dart';

/// Whose memories a turn retrieves: the RAG source character ids and the
/// session-scoped set (see [sourceIds]). Body as the generation part held
/// it; zero behaviour change.
class RagSources {
  RagSources(this._d);

  final PromptDeps _d;

  ChatSessionState get _session => _d.session;
  AppDatabase get _db => _d.services.db();
  CharacterRepository? get _characterRepository => _d.services.characters();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  String _getCharacterIdFromCard(CharacterCard c) => _session.characterIdFor(c);
  String _getCharacterId() => _session.ragCharacterId();

  /// Resolve the RAG source character ids for retrieval.
  ///
  /// Normally keyed on the active character. When a [guest] is supplied
  /// (Scene Guests Phase 4), retrieval is keyed on the guest's OWN id
  /// instead, plus that guest's cross-character memory sources, so the
  /// host's memories are never injected on a guest turn, and vice versa.
  ///
  /// Groups: memory is per member. The [speaker] reads only their own
  /// windows in this chat (filed under their [MemberMemory.keyFor]), their
  /// Data Bank and their memory sources; never another member's windows, so
  /// a scene they were Away for stays unknown to them. Windows from before
  /// per-member memory (see [legacyGroupMemoryBuckets]) are a read-only
  /// fallback for every member. [sessionScoped] limits the speaker's key and
  /// the fallback to this chat; explicit sources that are not members stay
  /// unscoped. A linked source keeps its other-chat windows, but in THIS chat
  /// a group speaker reads only [readableThisChat] (their own key and the old
  /// pool): anyone else's windows here may be scenes the speaker missed, so
  /// retrieval drops them, whoever they belong to.
  Future<
    ({
      List<String> sourceIds,
      Set<String> sessionScoped,
      Set<String> readableThisChat,
    })
  >
  sourceIds({CharacterCard? guest, CharacterCard? speaker}) async {
    final grouped = guest == null && _activeGroup != null;
    final memory = _d.doors.cast().memory;
    final currentId = guest != null
        ? _getCharacterIdFromCard(guest)
        : grouped
        ? (speaker == null ? '' : memory.keyFor(speaker))
        : _getCharacterId();
    final sourceIds = <String>[if (currentId.isNotEmpty) currentId];
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
      return (
        sourceIds: sourceIds,
        sessionScoped: sessionScoped,
        readableThisChat: const <String>{},
      );
    }

    if (grouped) {
      for (final bucket in legacyGroupMemoryBuckets(_activeGroup!.id)) {
        sourceIds.add(bucket);
        sessionScoped.add(bucket);
      }
      if (speaker != null) await addMemorySources(_libraryDbIdOf(speaker));
      // In this chat the speaker reads their own key and the old pool, and
      // nothing else: whoever else filed here, current, removed or renamed.
      return (
        sourceIds: sourceIds,
        sessionScoped: sessionScoped,
        readableThisChat: {
          if (currentId.isNotEmpty) currentId,
          ...legacyGroupMemoryBuckets(_activeGroup!.id),
        },
      );
    }

    await addMemorySources(_session.activeCharacter?.dbId);
    return (
      sourceIds: sourceIds,
      sessionScoped: sessionScoped,
      readableThisChat: const <String>{},
    );
  }

  /// The library row a group member was copied from (where its memory
  /// sources live); null for a member with no resolvable origin.
  String? _libraryDbIdOf(CharacterCard member) {
    final library = _characterRepository?.characters ?? const <CharacterCard>[];
    return MemberOriginResolver.libraryRagIdentity(
      originStableId: member.originStableId,
      originLibraryDbId: member.originLibraryDbId,
      memberName: member.name,
      libraryCharacters: library,
    ).libraryDbId;
  }

  /// Per-character memory importance, keyed the way retrieval multiplies:
  /// by the row owner's memory key. Stored by member roster id, so it is
  /// translated here; keying it by roster id never matched a row.
  Map<String, double> prioritiesByMemoryKey() {
    if (_activeGroup == null) return const {};
    final stored = _d.doors.entry().members.currentGroupRAGPriorities;
    final memory = _d.doors.cast().memory;
    return {
      for (final c in _groupCharacters)
        memory.keyFor(c): ?stored[_getCharacterIdFromCard(c)],
    };
  }
}
