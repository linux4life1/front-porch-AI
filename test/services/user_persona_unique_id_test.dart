// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Persona ids are millisecond timestamps, and every new one must be an id of
// its own, or its insert fails the personas table's unique key:
// - personas made in the same millisecond (CI saw it in
//   start_fresh_chat_test: the first persona a case created got the id of the
//   default persona the service was still seeding in the background);
// - personas imported from a file, two at a time;
// - a library whose stored ids run ahead of this computer's clock (made on
//   another machine, or a clock set back), deleted rows included.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// How many milliseconds of the clock, from now, a library "ahead of the
/// clock" has already used as ids: longer than any case here runs, so every
/// id the clock could give during a case is taken.
const _taken = 30000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory dir;

  setUp(() {
    // In memory on this isolate: each insert takes well under a millisecond.
    db = AppDatabase.forTesting(sameIsolate: true);
    dir = Directory.systemTemp.createTempSync('persona_ids_');
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// The service once its first load is in (on an empty library, that
  /// includes the default persona it seeds).
  Future<UserPersonaService> loaded() async {
    final personas = UserPersonaService(db);
    addTearDown(personas.dispose);
    final waiting = Stopwatch()..start();
    while (personas.personas.isEmpty) {
      if (waiting.elapsed > const Duration(seconds: 20)) {
        fail('the persona service never loaded its personas');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return personas;
  }

  /// Stores personas whose ids take every millisecond of the next [_taken]
  /// ms, and returns the highest. [deleted] rows are not in the persona
  /// list, so only the table's unique key sees them; a live "Kept" persona
  /// is stored beside them so the library is not empty.
  Future<int> idsAheadOfTheClock({required bool deleted}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.batch((batch) {
      batch.insertAll(db.personas, [
        for (var i = 0; i < _taken; i++)
          PersonasCompanion.insert(
            id: '${now + i}',
            name: Value('Stored $i'),
            deletedAt: Value(deleted ? DateTime.now() : null),
          ),
        if (deleted)
          PersonasCompanion.insert(id: 'kept', name: const Value('Kept')),
      ]);
    });
    return now + _taken - 1;
  }

  Future<String> personaFile(Object json) async {
    final file = File('${dir.path}/personas.json');
    await file.writeAsString(jsonEncode(json));
    return file.path;
  }

  Future<List<String>> names() async => [
    for (final row in await db.getAllPersonas()) row.name,
  ];

  test('personas begun in the same moment each get their own id', () async {
    final personas = await loaded();

    // Each create takes its id before its first await, so all ten are
    // given one within the same millisecond, as the seed and a create were.
    await Future.wait([
      for (var i = 0; i < 10; i++)
        personas.createPersona('Title $i', 'Name $i', '', null),
    ]);

    final rows = await db.getAllPersonas();
    expect({for (final row in rows) row.id}, hasLength(11));
    final titles = {for (final row in rows) row.title};
    for (var i = 0; i < 10; i++) {
      expect(titles, contains('Title $i'));
    }
  });

  test(
    'a library whose ids run ahead of the clock still gets new ids',
    () async {
      final highest = await idsAheadOfTheClock(deleted: false);
      final personas = await loaded();

      await personas.createPersona('Fresh', 'Fresh', '', null);

      expect(int.parse(personas.persona.id), greaterThan(highest));
    },
  );

  group('with every id near the clock already taken by deleted rows,', () {
    test('a two-persona SillyTavern import keeps both', () async {
      await idsAheadOfTheClock(deleted: true);
      final personas = await loaded();
      final path = await personaFile({
        'personas': {'linus.png': 'Linus', 'marta.png': 'Marta'},
        'persona_descriptions': {
          'linus.png': {'description': 'One.'},
          'marta.png': {'description': 'Two.'},
        },
      });

      expect(await personas.importFromJsonFile(path), isNotNull);
      expect(await names(), containsAll(['Linus', 'Marta']));
    });

    test('a file of two personas without ids, both named in the same '
        'millisecond, keeps both', () async {
      await idsAheadOfTheClock(deleted: true);
      final personas = await loaded();
      final path = await personaFile({
        'personas': [
          {'name': 'Ida', 'persona': ''},
          {'name': 'Jon', 'persona': ''},
        ],
      });

      expect(await personas.importFromJsonFile(path), isNotNull);
      expect(await names(), containsAll(['Ida', 'Jon']));
    });

    test('a file whose two ids repeat one already here gets new ids for '
        'both', () async {
      await idsAheadOfTheClock(deleted: true);
      final personas = await loaded();
      final path = await personaFile({
        'personas': [
          {'id': 'kept', 'name': 'Twin A', 'persona': ''},
          {'id': 'kept', 'name': 'Twin B', 'persona': ''},
        ],
      });

      expect(await personas.importFromJsonFile(path), isNotNull);
      expect(await names(), containsAll(['Kept', 'Twin A', 'Twin B']));
    });

    test('a single-persona file gets an id of its own', () async {
      await idsAheadOfTheClock(deleted: true);
      final personas = await loaded();
      final path = await personaFile({'name': 'Solo', 'description': 'Alone.'});

      expect(await personas.importFromJsonFile(path), isNotNull);
      expect(await names(), contains('Solo'));
    });
  });
}
