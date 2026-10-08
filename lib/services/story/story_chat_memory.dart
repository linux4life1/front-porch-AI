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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// One chat message as the Chat Distiller reads it, with where it sits.
typedef DistillLine = ({String sessionId, int position, String text});

/// The Journal cards and Growth Rings of the chats a story is distilled
/// from, each placed at the message it was first recorded against.
///
/// Both tables store message POSITIONS as receipts, so a card or ring lands
/// in the distiller chunk that holds that stretch of the chat. One with no
/// receipt (hand-written, or its messages are gone) is unplaced: cards go to
/// [closingNotes], where pinned cards and every ring appear regardless.
class StoryChatMemory {
  StoryChatMemory.place({
    required List<DistillLine> lines,
    required List<JournalMemoryData> cards,
    required List<GrowthRingData> rings,
    required this.names,
    required this.userName,
  }) {
    final firstOfSession = <String, List<int>>{};
    for (var i = 0; i < lines.length; i++) {
      firstOfSession.putIfAbsent(lines[i].sessionId, () => []).add(i);
    }
    int at(String sessionId, String? sources) {
      final first = _firstPosition(sources);
      if (first == null) return -1;
      for (final i in firstOfSession[sessionId] ?? const <int>[]) {
        if (lines[i].position >= first) return i;
      }
      return -1;
    }

    for (final c in cards) {
      if (c.content.trim().isEmpty) continue;
      _cards.add((at: at(c.sessionId, c.sourceMessageIds), card: c));
    }
    for (final r in rings) {
      if (r.content.trim().isEmpty) continue;
      _rings.add((at: at(r.sessionId, r.sourceMessageIds), ring: r));
    }
    _cards.sort((a, b) => a.at.compareTo(b.at));
    _rings.sort((a, b) => a.at.compareTo(b.at));
  }

  /// Journal / ring owner id (stableGroupId) → character name.
  final Map<String, String> names;
  final String userName;

  final List<({int at, JournalMemoryData card})> _cards = [];
  final List<({int at, GrowthRingData ring})> _rings = [];

  bool get isEmpty => _cards.isEmpty && _rings.isEmpty;

  /// The prompt block for the chunk covering lines [start, end): what the
  /// Journal and the rings already recorded in that stretch. Empty when
  /// nothing was.
  String chunkNotes(int start, int end) {
    bool inChunk(int at) => at >= start && at < end;
    final cards = _cards.where((c) => inChunk(c.at)).toList();
    final rings = _rings.where((r) => inChunk(r.at)).toList();
    if (cards.isEmpty && rings.isEmpty) return '';
    final b = StringBuffer();
    if (cards.isNotEmpty) {
      b.writeln(
        "CONFIRMED BY THE CHAT'S JOURNAL (these happened in this stretch of "
        'the conversation. Each MUST appear in the timeline, placed where '
        'the messages show it; take the detail and order from the messages):',
      );
      for (final c in cards) {
        b.writeln(_cardLine(c.card));
      }
      b.writeln();
    }
    if (rings.isNotEmpty) {
      b.writeln(
        'CHARACTER CHANGES FIRST SEEN IN THIS STRETCH (record each as an '
        'event at the point the messages show it):',
      );
      for (final r in rings) {
        b.writeln('- ${_ringText(r.ring)}');
      }
      b.writeln();
    }
    return b.toString();
  }

  /// Sections appended to the finished timeline: Journal cards tied to no
  /// moment, and every ring per character — who they are by the end, and
  /// the growth that has since faded.
  String closingNotes() {
    final b = StringBuffer();
    // Pinned cards are the ones the user marked as mattering: they are
    // restated here so a merge pass cannot lose them.
    final pinned = _cards.where((c) => c.at >= 0 && c.card.pinned).toList();
    if (pinned.isNotEmpty) {
      b.writeln(
        "PINNED IN THE CHAT'S JOURNAL (in chat order; each of these "
        'happened, whether or not an event above names it):',
      );
      for (final c in pinned) {
        b.writeln(_cardLine(c.card));
      }
    }
    final loose = _cards.where((c) => c.at < 0).toList();
    if (loose.isNotEmpty) {
      if (b.isNotEmpty) b.writeln();
      b.writeln(
        "ALSO ESTABLISHED (from the chat's journal; true, but not tied to "
        'one moment):',
      );
      for (final c in loose) {
        b.writeln(_cardLine(c.card));
      }
    }
    if (_rings.isNotEmpty) {
      if (b.isNotEmpty) b.writeln();
      b.writeln(
        'HOW THE CHARACTERS CHANGED OVER THIS CHAT (their definitions '
        'describe who they were at the START; write the arc from that to '
        'this):',
      );
      final owners = <String>{for (final r in _rings) r.ring.characterId};
      for (final owner in owners) {
        final mine = _rings.where((r) => r.ring.characterId == owner);
        final active = mine.where((r) => !r.ring.retired).toList()
          ..sort((a, b) => b.ring.strength.compareTo(a.ring.strength));
        final faded = mine.where((r) => r.ring.retired).toList();
        final name = _nameOf(owner);
        if (active.isNotEmpty) {
          b.writeln('$name, by the end:');
          for (final r in active) {
            b.writeln(
              '- (${r.ring.category}, ${GrowthPhysics.tierOf(r.ring)}) '
              '${_ringText(r.ring)}',
            );
          }
        }
        if (faded.isNotEmpty) {
          b.writeln(
            '$name, earlier growth that has since faded (part of the arc, '
            'no longer true at the end):',
          );
          for (final r in faded) {
            b.writeln('- (${r.ring.category}) ${_ringText(r.ring)}');
          }
        }
      }
    }
    return b.toString().trim();
  }

  String _nameOf(String ownerId) => names[ownerId] ?? 'The character';

  String _cardLine(JournalMemoryData c) {
    final feeling = c.emotionLabel?.trim() ?? '';
    return "- ${_nameOf(c.characterId)}'s journal"
        '${feeling.isEmpty ? '' : ' (feeling $feeling)'}: ${c.content.trim()}';
  }

  String _ringText(GrowthRingData r) => resolveGrowthMacros(
    r.content.trim(),
    charName: names[r.characterId],
    userName: userName,
  );

  static int? _firstPosition(String? sources) {
    final positions = decodeReceiptIds(sources);
    if (positions.isEmpty) return null;
    return positions.reduce((a, b) => a < b ? a : b);
  }
}
