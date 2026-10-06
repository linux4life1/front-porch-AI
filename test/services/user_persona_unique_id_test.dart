// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Persona ids are millisecond timestamps. Personas made in the same
// millisecond must still get ids of their own, or the second insert fails
// the personas table's unique key. CI saw it in start_fresh_chat_test: the
// first persona a case created got the id of the default persona that the
// service was still seeding in the background.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('personas begun in the same moment each get their own id', () async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    final personas = UserPersonaService(db);
    addTearDown(() async {
      personas.dispose();
      await db.close();
    });
    while (personas.personas.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

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
}
