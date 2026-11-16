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
import 'package:front_porch_ai/services/chat/doors/cast/cast_deps.dart';
import 'package:front_porch_ai/services/chat/doors/cast/away_pulse_runner.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/services/chat/presence_derive.dart';

/// Who a group's memories belong to: each member's memory key, and who was
/// present for a line when it was written. Memory is per member (ruling 8:
/// a character recalls only what they were there for), so the writer files a
/// window under each member who was present, and the reader reads the
/// speaker's own key.
class MemberMemory {
  MemberMemory(this._away, this._d);

  final AwayPulseRunner _away;
  final CastDeps _d;

  List<CharacterCard> get _library =>
      _d.characters()?.characters ?? const <CharacterCard>[];

  /// [card]'s memory key (see [memoryKeyFor]).
  String keyFor(CharacterCard card) => memoryKeyFor(card, _library);

  /// The open group's members by memory key; empty outside a group.
  Set<String> rosterKeys() => {
    if (_d.session.activeGroup != null)
      for (final c in _d.session.groupCharacters) keyFor(c),
  };

  /// Keys of the members in the scene now: not Away and not At work (the
  /// same read the turn picker skips on), plus [speaker], who is there by
  /// speaking.
  Set<String> presentKeys({CharacterCard? speaker}) {
    final out = <String>{};
    for (final c in _d.session.groupCharacters) {
      final where = _away.groupMemberPresence(_d.characterIdFor(c));
      if (where == null || !groupTurnSkips(where)) out.add(keyFor(c));
    }
    if (speaker != null) out.add(keyFor(speaker));
    return out;
  }

  /// Stamps [msg] with who is present now, in a group. A no-op in a 1:1.
  void stamp(ChatMessage msg, {CharacterCard? speaker}) {
    if (_d.session.activeGroup == null) return;
    final meta = msg.activeMetadata ?? <String, dynamic>{};
    meta[kMemoryPresentMeta] = presentKeys(speaker: speaker).toList()..sort();
    msg.activeMetadata = meta;
  }
}
