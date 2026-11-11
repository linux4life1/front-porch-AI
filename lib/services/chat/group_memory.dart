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
import 'package:front_porch_ai/services/chat/member_origin_resolver.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Message-metadata key listing the memory keys of the group members who
/// were there when the message was written (a sorted list of strings). Stamped
/// on every user line and every reply in a group; read when a window is filed.
const String kMemoryPresentMeta = 'memory_present';

/// The key a group member's windows are filed under: their library identity
/// (the origin character's `stableGroupId`, which Data Bank rows and memory
/// sources also use), or, for a member with no resolvable origin, their own
/// store id ([groupMemberStoreId], the id the group-load re-key moves legacy
/// rows onto, so the two can never disagree). Never the roster UUID of a
/// library-backed member, and never changed by a lite guest's promotion
/// (tier is not part of identity).
String memoryKeyFor(CharacterCard card, Iterable<CharacterCard> library) {
  final ident = MemberOriginResolver.libraryRagIdentity(
    originStableId: card.originStableId,
    originLibraryDbId: card.originLibraryDbId,
    memberName: card.name,
    libraryCharacters: library,
  );
  final sid = ident.sourceId;
  return (sid != null && sid.isNotEmpty) ? sid : groupMemberStoreId(card);
}

/// THE decision about windows written before per-member memory: they sit
/// under one shared id per group (`group_<id>`). Today they stay as a
/// read-only fallback that every member reads (same chat only), so an
/// existing chat keeps its memories, and nothing re-files them. To change
/// that (re-file per member, or drop them), change only this function and
/// its two callers: the speaker's read sources and the writer's skip list.
List<String> legacyGroupMemoryBuckets(String groupId) => ['group_$groupId'];

/// For each member key in [rosterKeys], one flag per line of [messages]:
/// whether that member was present for it.
///
/// A message carries its own stamp ([kMemoryPresentMeta]). One without a stamp
/// (a narration, a note, a banner) was seen by whoever the last stamped line
/// before it was; unstamped lines before any stamp (a chat from before
/// per-member memory, an imported one) say nothing about presence, so the
/// whole roster counts as present.
Map<String, List<bool>> presentLineMasks(
  List<ChatMessage> messages,
  Iterable<String> rosterKeys,
) {
  final roster = rosterKeys.toSet();
  final masks = {
    for (final k in roster) k: List<bool>.filled(messages.length, false),
  };
  Set<String>? last;
  for (var i = 0; i < messages.length; i++) {
    final stamp = messages[i].activeMetadata?[kMemoryPresentMeta];
    if (stamp is List) {
      last = {for (final e in stamp) e.toString()};
    }
    final seen = last ?? roster;
    for (final k in roster) {
      masks[k]![i] = seen.contains(k);
    }
  }
  return masks;
}
