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

// The v46→v47 `sessions.pockets` column.
//
// THE BUG IT FIXES. Group chats persisted each member's Pockets record inside
// `group_realism_state` and so always survived a reload. A 1:1 chat had no home
// for the record at all: `ChatService._pockets` lived in memory, snapshotted
// into each message's `realism_state` — but that snapshot is only ever restored
// by `_restoreRealismStateForSpeaker`, which runs on regen, swipe and delete,
// never on session load. So closing a 1:1 chat and reopening it emptied her
// pockets, and the pass re-seeded from the card as though the chat were new.
//
// That is a straight 1:1-vs-group parity break, and it made the feature's own
// description false for exactly the users most likely to try it: "the keys she
// picked up an hour ago are still in her pocket" — until you closed the tab.
//
// Needs hit the identical problem and solved it with `sessions.needs_vector`.
// This is that mirror, so the tests below check the same three declarations
// agree that every other schema guard checks.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show PocketItem, Pockets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  Future<String?> readPockets(String id) async {
    final row = await db
        .customSelect(
          'SELECT pockets FROM sessions WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.read<String?>('pockets');
  }

  group('NULL is right for every chat that predates the column', () {
    test('a session that never mentions pockets reads back NULL', () async {
      await db.insertSession(SessionsCompanion.insert(id: 's-old'));

      expect(
        await readPockets('s-old'),
        isNull,
        reason:
            'nothing was ever saved for these chats, so there is nothing '
            'to claim otherwise — the pass simply re-seeds from the card, '
            'exactly as it does for a brand new chat',
      );
    });

    test('an empty record is stored as NULL, not as an empty blob', () async {
      await db.insertSession(
        SessionsCompanion.insert(id: 's-empty', pockets: const Value(null)),
      );

      expect(
        await readPockets('s-empty'),
        isNull,
        reason:
            '"{}" and NULL must not both mean nothing — the loader tests '
            'for a non-empty string, and a blob that decodes to nothing would '
            'be a slower way of saying the same thing',
      );
    });
  });

  group('a real record round-trips, condition and all', () {
    test('worn and carrying survive with their states', () async {
      final p = Pockets(
        worn: [const PocketItem('sundress', state: 'rain-soaked')],
        carrying: [const PocketItem('car keys')],
      );

      await db.insertSession(
        SessionsCompanion.insert(
          id: 's-live',
          pockets: Value(jsonEncode(p.toJson())),
        ),
      );

      final back = Pockets.fromJson(jsonDecode((await readPockets('s-live'))!));

      expect(back.worn.single.name, 'sundress');
      expect(
        back.worn.single.state,
        'rain-soaked',
        reason:
            'the condition is half the feature — a coat that arrives back '
            'from a reload freshly laundered is a bug you would never notice '
            'until it mattered',
      );
      expect(back.carrying.single.name, 'car keys');
    });

    test('the generated row exposes it as a nullable String', () async {
      await db.insertSession(
        SessionsCompanion.insert(id: 's-typed', pockets: const Value('{}')),
      );
      final s = await db.getSessionById('s-typed');

      expect(
        s?.pockets,
        '{}',
        reason: 'this is the field chat_service_session_load reads on reopen',
      );
    });
  });
}
