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

import 'package:drift/drift.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/persona/message_persona.dart';
import 'package:front_porch_ai/services/persona/user_persona.dart';

/// One turn of a Backyard AI chat history.
///
/// An AI turn carries every regeneration Backyard kept ([swipes]) and which
/// one was on screen ([activeIndex]), so none is lost on import.
class ByafChatMessage {
  final String type; // 'ai' or 'human'
  final List<String> swipes;
  final int activeIndex;
  final DateTime? createdAt;

  ByafChatMessage({
    required this.type,
    required this.swipes,
    this.activeIndex = 0,
    this.createdAt,
  });

  /// The text Backyard showed for this turn.
  String get text => swipes[activeIndex];
}

/// Convert Backyard AI placeholders {character}/{user} to V2 {{char}}/{{user}}.
String convertByafPlaceholders(String text) {
  return text
      .replaceAll('{character}', '{{char}}')
      .replaceAll('{Character}', '{{char}}')
      .replaceAll('{CHARACTER}', '{{char}}')
      .replaceAll('{user}', '{{user}}')
      .replaceAll('{User}', '{{user}}')
      .replaceAll('{USER}', '{{user}}');
}

/// Read a scenario's `messages` array. Turns with no text are dropped.
///
/// An AI turn's `outputs` are its regenerations. The one Backyard showed is
/// the output with the latest `activeTimestamp`; when none carries one, the
/// first output stands (older exports).
List<ByafChatMessage> parseByafChatMessages(Object? raw) {
  final out = <ByafChatMessage>[];
  if (raw is! List) return out;
  for (final msg in raw) {
    if (msg is! Map) continue;
    final type = msg['type']?.toString() ?? '';
    if (type == 'human') {
      final text = msg['text']?.toString() ?? '';
      if (text.isEmpty) continue;
      out.add(
        ByafChatMessage(
          type: type,
          swipes: [text],
          createdAt: DateTime.tryParse(msg['createdAt']?.toString() ?? ''),
        ),
      );
    } else if (type == 'ai') {
      final swipes = <String>[];
      var activeIndex = 0;
      DateTime? activeAt;
      DateTime? createdAt;
      final outputs = msg['outputs'];
      if (outputs is! List) continue;
      for (final output in outputs) {
        if (output is! Map) continue;
        final text = output['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        final shownAt = DateTime.tryParse(
          output['activeTimestamp']?.toString() ?? '',
        );
        if (shownAt != null &&
            (activeAt == null || shownAt.isAfter(activeAt))) {
          activeAt = shownAt;
          activeIndex = swipes.length;
          createdAt = DateTime.tryParse(output['createdAt']?.toString() ?? '');
        }
        createdAt ??= DateTime.tryParse(output['createdAt']?.toString() ?? '');
        swipes.add(text);
      }
      if (swipes.isEmpty) continue;
      out.add(
        ByafChatMessage(
          type: type,
          swipes: swipes,
          activeIndex: activeIndex,
          createdAt: createdAt,
        ),
      );
    }
  }
  return out;
}

/// The message rows for an imported Backyard chat, in order.
///
/// Backyard keeps the scenario's opening message outside its history, so
/// [firstMessage] becomes the first bubble here, as in any new chat (with
/// names filled in the way a new chat's greeting is). User turns are
/// stamped with [persona] so they show and prompt as that persona, not
/// "User".
List<MessagesCompanion> byafSessionRows({
  required String sessionId,
  required List<ByafChatMessage> messages,
  required String characterName,
  required UserPersona persona,
  String? firstMessage,
}) {
  final rows = <MessagesCompanion>[];
  void add({
    required bool isUser,
    required List<String> swipes,
    int swipeIndex = 0,
  }) {
    rows.add(
      MessagesCompanion(
        sessionId: Value(sessionId),
        position: Value(rows.length),
        sender: Value(isUser ? persona.name : characterName),
        isUser: Value(isUser),
        swipes: Value(jsonEncode(swipes)),
        swipeIndex: Value(swipeIndex),
        metadata: isUser
            ? Value(jsonEncode({kUserPersonaIdMeta: persona.id}))
            : const Value.absent(),
      ),
    );
  }

  final opener = convertByafPlaceholders(firstMessage ?? '').trim();
  final firstAi = messages.isNotEmpty && messages.first.type == 'ai'
      ? convertByafPlaceholders(messages.first.text).trim()
      : null;
  // Some exports already open with the greeting; never show it twice.
  if (opener.isNotEmpty && opener != firstAi) {
    add(
      isUser: false,
      swipes: [
        opener
            .replaceAll('{{char}}', characterName)
            .replaceAll('{{user}}', persona.name),
      ],
    );
  }
  for (final msg in messages) {
    add(
      isUser: msg.type == 'human',
      swipes: msg.swipes.map(convertByafPlaceholders).toList(),
      swipeIndex: msg.activeIndex,
    );
  }
  return rows;
}

/// The persona a Backyard chat was most likely written as, or null.
///
/// The archive never names the user, but Backyard writes the user's name
/// into replies ("Back so soon, Sam?") and people write it into their
/// own narration, so each persona's name is counted as a whole word, any
/// case, across every turn and regeneration. The most-named persona wins;
/// a tie between different names, or no hits, recommends nobody. Among
/// same-named personas the [defaultId] one is preferred, else the first.
String? recommendByafPersonaId(
  List<ByafChatMessage> messages,
  List<UserPersona> personas, {
  String? defaultId,
}) {
  final hitsByName = <String, int>{};
  for (final p in personas) {
    final key = p.name.trim().toLowerCase();
    if (key.isEmpty || hitsByName.containsKey(key)) continue;
    final word = RegExp(
      '(?<![\\p{L}\\p{N}_])${RegExp.escape(key)}(?![\\p{L}\\p{N}_])',
      caseSensitive: false,
      unicode: true,
    );
    var hits = 0;
    for (final m in messages) {
      for (final s in m.swipes) {
        hits += word.allMatches(s).length;
      }
    }
    hitsByName[key] = hits;
  }
  final best = hitsByName.values.fold(0, (a, b) => a > b ? a : b);
  if (best == 0) return null;
  final winners = [
    for (final e in hitsByName.entries)
      if (e.value == best) e.key,
  ];
  if (winners.length != 1) return null;
  final named = [
    for (final p in personas)
      if (p.name.trim().toLowerCase() == winners.single) p,
  ];
  return named
      .firstWhere((p) => p.id == defaultId, orElse: () => named.first)
      .id;
}
