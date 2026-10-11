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
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/utils/think_tags.dart';

/// What you and one character have said to each other, across their 1:1 chats.
///
/// Group chats are not counted: a group member is a copy of the card that
/// lives inside the group, not the library character.
class CharacterStats {
  final int chats;
  final int theirMessages;
  final int yourMessages;
  final int theirWords;
  final int yourWords;
  final int longestChat;
  final DateTime? firstChat;
  final DateTime? lastChat;

  const CharacterStats({
    this.chats = 0,
    this.theirMessages = 0,
    this.yourMessages = 0,
    this.theirWords = 0,
    this.yourWords = 0,
    this.longestChat = 0,
    this.firstChat,
    this.lastChat,
  });

  bool get isEmpty => theirMessages + yourMessages == 0;

  Map<String, dynamic> toJson() => {
    'chats': chats,
    'theirMessages': theirMessages,
    'yourMessages': yourMessages,
    'theirWords': theirWords,
    'yourWords': yourWords,
    'longestChat': longestChat,
    'firstChat': firstChat?.toIso8601String(),
    'lastChat': lastChat?.toIso8601String(),
  };
}

/// One stored message, reduced to what the counts need.
typedef StatsMessageRow = ({
  String sessionId,
  bool isUser,
  String? characterId,
  String swipes,
  int swipeIndex,
});

final _wordRe = RegExp(r'\S+');

/// Counts [rows] (one character's 1:1 messages). Pure; runs off the UI isolate.
CharacterStats countCharacterStats(
  List<StatsMessageRow> rows, {
  required int chats,
  DateTime? firstChat,
  DateTime? lastChat,
}) {
  var theirMessages = 0, yourMessages = 0, theirWords = 0, yourWords = 0;
  final perChat = <String, int>{};
  for (final r in rows) {
    if (r.characterId == '__director__') continue;
    final words = _wordRe.allMatches(stripThinkTags(_shownSwipe(r))).length;
    if (words == 0) continue;
    perChat[r.sessionId] = (perChat[r.sessionId] ?? 0) + 1;
    if (r.isUser) {
      yourMessages++;
      yourWords += words;
    } else {
      theirMessages++;
      theirWords += words;
    }
  }
  var longest = 0;
  for (final n in perChat.values) {
    if (n > longest) longest = n;
  }
  return CharacterStats(
    chats: chats,
    theirMessages: theirMessages,
    yourMessages: yourMessages,
    theirWords: theirWords,
    yourWords: yourWords,
    longestChat: longest,
    firstChat: firstChat,
    lastChat: lastChat,
  );
}

String _shownSwipe(StatsMessageRow r) {
  try {
    final list = jsonDecode(r.swipes);
    if (list is! List || list.isEmpty) return '';
    final i = r.swipeIndex.clamp(0, list.length - 1);
    return '${list[i] ?? ''}';
  } on FormatException {
    return '';
  }
}

/// Loads and counts the stats for the library character [characterId]
/// (`characters.id`, the id 1:1 sessions are bound to).
Future<CharacterStats> loadCharacterStats(
  AppDatabase db,
  String characterId,
) async {
  final sessions = await db
      .customSelect(
        'SELECT COUNT(*) AS n, MIN(created_at) AS first_at, '
        'MAX(updated_at) AS last_at FROM sessions '
        'WHERE character_id = ? AND deleted_at IS NULL',
        variables: [Variable.withString(characterId)],
      )
      .getSingle();
  final chats = sessions.read<int>('n');
  if (chats == 0) return const CharacterStats();

  final rows = await db
      .customSelect(
        'SELECT m.session_id, m.is_user, m.character_id, m.swipes, '
        'm.swipe_index FROM messages m '
        'JOIN sessions s ON s.id = m.session_id '
        'WHERE s.character_id = ? AND s.deleted_at IS NULL '
        'AND m.deleted_at IS NULL',
        variables: [Variable.withString(characterId)],
      )
      .get();
  final reduced = [
    for (final r in rows)
      (
        sessionId: r.read<String>('session_id'),
        isUser: r.read<bool>('is_user'),
        characterId: r.readNullable<String>('character_id'),
        swipes: r.read<String>('swipes'),
        swipeIndex: r.read<int>('swipe_index'),
      ),
  ];
  final firstChat = sessions.readNullable<DateTime>('first_at');
  final lastChat = sessions.readNullable<DateTime>('last_at');
  return Isolate.run(
    () => countCharacterStats(
      reduced,
      chats: chats,
      firstChat: firstChat,
      lastChat: lastChat,
    ),
  );
}

/// The web editor's "Your chats together" payload, or null when [id] is not a
/// library character. Same counts as the desktop Details tab.
Future<Map<String, dynamic>?> characterStatsJson(
  AppDatabase db,
  String id,
) async {
  final exists = await (db.select(
    db.characters,
  )..where((c) => c.id.equals(id))).getSingleOrNull();
  if (exists == null) return null;
  return (await loadCharacterStats(db, id)).toJson();
}
