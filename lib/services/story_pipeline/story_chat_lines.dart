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
import 'package:front_porch_ai/database/database.dart' hide StoryProject;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/director/director.dart';
import 'package:front_porch_ai/services/story/story.dart';

/// The messages of the chats a story is built on, as the distiller, the
/// preview and the raw canon fallback all read them. One loader, so the
/// three cannot disagree about which chats are "the chat history".
///
/// A group chat's lines name their speaker from the message's own speaker
/// id through the group's roster, never from the stored sender name alone
/// and never from whoever is active in the chat
/// (docs/design/stories-from-group-chats.md §2).
class StoryChatLines {
  StoryChatLines(this._db);

  final AppDatabase _db;

  /// Roster names per group id, cleared at the start of every public read
  /// so a renamed member or a failed read never outlives the call.
  final Map<String, Map<String, String>> _rosters = {};

  /// The sessions [project] reads. A listed session is loaded by id (a
  /// group session has no character id of its own); without a list, every
  /// session of [characterIds], the pre-Living-Time contract.
  Future<List<Session>> sessionsFor(
    StoryProject project,
    Iterable<String> characterIds,
  ) async {
    if (project.chatHistorySessionIds.isNotEmpty) {
      final out = <Session>[];
      for (final id in project.chatHistorySessionIds) {
        final s = await _db.getSessionById(id);
        if (s != null && s.deletedAt == null) out.add(s);
      }
      return out;
    }
    final out = <Session>[];
    for (final charId in characterIds) {
      out.addAll(await _db.getSessionsForCharacter(charId));
    }
    return out;
  }

  /// Every line of [session], `Name: text`, oldest first. Empty swipes and
  /// rows that fail to decode are skipped, as they always were.
  Future<List<DistillLine>> linesFor(Session session) async {
    _rosters.clear();
    final roster = await _rosterFor(session.groupId);
    final lines = <DistillLine>[];
    for (final msg in await _db.getMessagesForSession(session.id)) {
      final line = _lineOf(msg, roster);
      if (line == null) continue;
      lines.add((
        sessionId: session.id,
        position: msg.position,
        text: '${line.who}: ${line.text}',
      ));
    }
    return lines;
  }

  /// The whole history of [project]: its lines in session order, the
  /// session ids read, the user's name (the first user line's sender) and
  /// the speakers beside the user. A group's speakers are its roster in
  /// roster order, even members who never spoke; a 1:1 chat's are the
  /// senders that appeared.
  Future<StoryChatHistoryLoad> load(
    StoryProject project,
    Iterable<String> characterIds,
  ) async {
    _rosters.clear();
    final sessions = await sessionsFor(project, characterIds);
    final lines = <DistillLine>[];
    final sessionIds = <String>[];
    final speakers = <String>[];
    var userName = '';
    for (final session in sessions) {
      sessionIds.add(session.id);
      final roster = await _rosterFor(session.groupId);
      for (final name in roster.values) {
        if (!speakers.contains(name)) speakers.add(name);
      }
      for (final msg in await _db.getMessagesForSession(session.id)) {
        final line = _lineOf(msg, roster);
        if (line == null) continue;
        switch (line.kind) {
          case _LineKind.user:
            if (userName.isEmpty) userName = line.who;
          case _LineKind.character:
            if (!speakers.contains(line.who)) speakers.add(line.who);
          case _LineKind.narration:
            break;
        }
        lines.add((
          sessionId: session.id,
          position: msg.position,
          text: '${line.who}: ${line.text}',
        ));
      }
    }
    return StoryChatHistoryLoad(
      lines: lines,
      sessionIds: sessionIds,
      userName: userName,
      speakers: speakers,
      isGroup:
          project.chatGroupId != null || sessions.any((s) => s.groupId != null),
    );
  }

  /// What one stored row contributes to the history. A narrator beat
  /// (`/narrate`, a time-skip bridge) is scene text and stays, as
  /// `Narration:`, but names no speaker and is not the user. A director's
  /// note is an instruction to the cast, and a status banner is the app
  /// talking; neither is story, so both are left out.
  static ({_LineKind kind, String who, String text})? _lineOf(
    Message msg,
    Map<String, String> roster,
  ) {
    final text = _textOf(msg);
    if (text.isEmpty) return null;
    final meta = _metaOf(msg);
    if (meta[kStatusBannerMeta] == true) return null;
    if (msg.characterId == kDirectorCharacterId) {
      if (meta[kDirectorNarrationMeta] != true) return null;
      return (kind: _LineKind.narration, who: 'Narration', text: text);
    }
    if (msg.isUser) return (kind: _LineKind.user, who: msg.sender, text: text);
    final member = roster[msg.characterId];
    if (member != null) {
      return (kind: _LineKind.character, who: member, text: text);
    }
    // A presence skip or any other app line the chat wrote as `System`.
    if (msg.sender == 'System') return null;
    return (kind: _LineKind.character, who: msg.sender, text: text);
  }

  static Map<String, dynamic> _metaOf(Message msg) {
    final raw = msg.metadata;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (e) {
      debugPrint('[StoryPipeline] Unreadable message metadata: $e');
      return const {};
    }
  }

  Future<Map<String, String>> _rosterFor(String? groupId) async {
    if (groupId == null) return const {};
    final cached = _rosters[groupId];
    if (cached != null) return cached;
    final names = <String, String>{};
    try {
      for (final row in await _db.getGroupMembers(groupId)) {
        names[row.id] = row.name;
      }
    } catch (e) {
      debugPrint('[StoryPipeline] Group roster load failed: $e');
    }
    return _rosters[groupId] = names;
  }

  static String _textOf(Message msg) {
    try {
      final swipes = jsonDecode(msg.swipes) as List;
      if (swipes.isEmpty) return '';
      return swipes[msg.swipeIndex.clamp(0, swipes.length - 1)]
          .toString()
          .trim();
    } catch (_) {
      return '';
    }
  }
}

enum _LineKind { user, character, narration }

/// What [StoryChatLines.load] found.
class StoryChatHistoryLoad {
  const StoryChatHistoryLoad({
    required this.lines,
    required this.sessionIds,
    required this.userName,
    required this.speakers,
    required this.isGroup,
  });

  final List<DistillLine> lines;
  final List<String> sessionIds;
  final String userName;
  final List<String> speakers;

  /// The chat was a group scene: several characters, each in their own
  /// voice.
  final bool isGroup;

  bool get isEmpty => lines.isEmpty;

  /// Who is talking, for the distiller and the canon block. A 1:1 chat
  /// keeps the one-character wording; a group names every speaker and asks
  /// for the speaker on every event (docs/design/stories-from-group-chats.md
  /// §2, §3).
  String castSentence() {
    final user = userName.isEmpty ? 'the user' : userName;
    if (!isGroup) {
      return 'The conversation is between a user ($user) and an AI character'
          '${speakers.isEmpty ? '' : ' (${speakers.first})'}.';
    }
    return 'The conversation is a group scene: the characters are '
        '${joinCastNames(speakers)}, each speaking for themselves; the user '
        'plays $user. Name the speaker in every event. Keep every one of '
        'these characters as themselves: do not fold two of them into one, '
        'and do not drop one because another carries more of the story.';
  }
}
