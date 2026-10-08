// The Settings cleanup removes chats that no character or group owns any more
// with a query of its own, not through deleteSessionById. It gives the same
// word every other delete gives, so what lives outside the database for a
// chat (KoboldCpp's saved cache of it) goes with it.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/database/database_cleanup.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
  tearDown(() async => db.close());

  test('the chats the cleanup removes are told like any deleted chat, and '
      'only those', () async {
    final told = <String>[];
    db.deletedSessions.listen(told.add);
    await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(id: 'g-live', name: 'Porch Duo'));
    await db.insertSession(
      SessionsCompanion.insert(id: 's-live', groupId: const Value('g-live')),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 's-no-character',
        characterId: const Value('a-character-that-is-gone'),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 's-no-group',
        groupId: const Value('a-group-that-is-gone'),
      ),
    );

    final result = await DatabaseCleanup.cleanOrphans(db);

    expect(result.removedCounts['sessions'], 1);
    expect(result.removedCounts['group_orphan_sessions'], 1);
    expect(told, unorderedEquals(['s-no-character', 's-no-group']));
  });
}
