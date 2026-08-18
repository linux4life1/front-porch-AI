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
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show PocketItem, Pockets;

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
        reason: 'nothing was ever saved for these chats, so there is nothing '
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
        reason: '"{}" and NULL must not both mean nothing — the loader tests '
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
        reason: 'the condition is half the feature — a coat that arrives back '
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

  group('the three declarations of this column agree', () {
    final table = File(
      'lib/database/database.tables.core.dart',
    ).readAsStringSync();
    final ladder = File(
      'lib/database/database.migrations.dart',
    ).readAsStringSync();
    final repair = File('lib/database/database.repair.dart').readAsStringSync();

    test('the Table declares it nullable with no default', () {
      expect(table, contains('get pockets => text().nullable()()'));
      expect(
        table.contains('get pockets => text().nullable().withDefault'),
        isFalse,
        reason: 'a default would give pre-v47 chats an invented record',
      );
    });

    test('the ladder adds a plain nullable TEXT', () {
      expect(
        ladder,
        contains('ALTER TABLE sessions ADD COLUMN pockets TEXT'),
      );
      expect(ladder.contains('pockets TEXT NOT NULL'), isFalse);
    });

    test('the repair path matches both', () {
      expect(repair, contains("'pockets TEXT'"));
    });

    test('schemaVersion is at least 47', () {
      final src = File('lib/database/database.dart').readAsStringSync();
      final m = RegExp(r'schemaVersion => (\d+)').firstMatch(src);
      expect(m, isNotNull);
      expect(
        int.parse(m!.group(1)!),
        greaterThanOrEqualTo(47),
        reason: 'the v47 ladder step is dead code if the version never asks for it',
      );
    });
  });

  group('the 1:1 record is actually wired to save and load', () {
    // Structural, and labelled as such: proving it behaviourally needs a live
    // ChatService opening and closing a real chat. Read it as "the wiring
    // exists", not "the record survives".
    //
    // It is here because the bug was precisely a MISSING wire — the column
    // could exist and be perfect and the chat would still forget, which is the
    // shape of every silent failure found in this feature so far.
    test('session state writes it', () {
      final src = File(
        'lib/services/chat/chat_service_session_state.dart',
      ).readAsStringSync();

      expect(src, contains('pockets: drift.Value('));
      expect(
        src,
        contains('_activeGroup == null'),
        reason: 'only the 1:1 scalar belongs here — group members ride '
            'groupRealismState and writing them twice would let the two '
            'copies disagree',
      );
    });

    test('session load restores it', () {
      final src = File(
        'lib/services/chat/chat_service_session_load.dart',
      ).readAsStringSync();

      expect(src, contains('s.pockets'));
      expect(
        src,
        contains('Pockets.fromJson'),
        reason: 'reading the column and not parsing it back into the record '
            'is the same bug wearing a different hat',
      );
    });
  });

  group('the paths that must NOT carry a record across', () {
    // Storing the record turned two pre-existing, invisible leaks into
    // permanent ones, so they are fixed in the same change and pinned here.
    //
    // Structural, and for the same reason as the group above: these are field
    // assignments inside orchestration that needs a live ChatService, a live
    // database and a real character to reach. The suites next door test
    // hand-written stubs of that orchestration, which would only prove the stub
    // resets its own field. Anchored on the neighbouring needs reset so that
    // deleting the line — the actual regression — fails, rather than merely
    // asserting the string exists somewhere in the file.

    /// Every `clearVector()` reset block, as the text between that call and the
    /// following 12 lines. `_pockets = null` belongs in each of them.
    List<String> resetBlocksIn(String path) {
      final src = File(path).readAsStringSync();
      final lines = src.split('\n');
      return [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].contains('_needsSimulation.clearVector()'))
            lines.sublist(i, (i + 12).clamp(0, lines.length)).join('\n'),
      ];
    }

    test('a fresh 1:1 chat starts with empty hands', () {
      final blocks = resetBlocksIn(
        'lib/services/chat/chat_service_chat_entry.dart',
      );
      expect(blocks, isNotEmpty, reason: 'the reset block moved or was renamed');
      expect(
        blocks.any((b) => b.contains('_pockets = null')),
        isTrue,
        reason: 'without this the new chat opens with the LAST chat\'s props '
            'still in her hands, and the first save writes them into the new '
            "chat's row — where they are indistinguishable from something she "
            'actually picked up',
      );
    });

    test('both fresh-chat branches in session_manage clear it', () {
      final blocks = resetBlocksIn(
        'lib/services/chat/chat_service_session_manage.dart',
      );
      expect(
        blocks.length,
        greaterThanOrEqualTo(2),
        reason: 'there are two: the ext-seed branch and the plain one. A fix '
            'applied to only one leaves the bleed alive on the other path',
      );
      for (final b in blocks) {
        expect(b, contains('_pockets = null'));
      }
    });

    test('a group collapsing to 1:1 carries the survivor record over', () {
      final src = File(
        'lib/services/chat/chat_service_cast.dart',
      ).readAsStringSync();

      expect(
        src,
        contains('_groupRealism[soleId]?.pockets'),
        reason: 'it must be read BEFORE the re-home: step 4 re-enters as a 1:1, '
            'which clears _groupRealism, so reading it afterwards finds nothing',
      );
      expect(
        src,
        contains('_pockets = solePockets'),
        reason: 'capturing it and never restoring it is the same loss with '
            'extra steps — the survivor walks out of the group empty-handed',
      );
      expect(
        src.indexOf('_groupRealism[soleId]?.pockets'),
        lessThan(src.indexOf('_pockets = solePockets')),
        reason: 'capture must precede restore',
      );
    });
  });
}
