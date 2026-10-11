// The phone's character editor reads "Your chats together" from the same
// counts the desktop Details tab shows.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_stats.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/character_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.createTempSync('fpai_test_').path,
      );
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late CharacterFacade facade;

  setUp(() async {
    db = AppDatabase.forTesting();
    facade = CharacterFacade(db, StorageService(), null, null, null);
    await db.insertCharacter(
      const CharactersCompanion(id: Value('c1'), name: Value('Alice')),
    );
    await db.insertSession(
      SessionsCompanion.insert(id: 's1', characterId: const Value('c1')),
    );
    var pos = 0;
    for (final (isUser, text) in [(false, 'Hello there'), (true, 'Hi')]) {
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'm$pos',
              sessionId: 's1',
              position: pos++,
              sender: isUser ? 'You' : 'Alice',
              isUser: isUser,
              swipes: Value(jsonEncode([text])),
            ),
          );
    }
  });

  tearDown(() => db.close());

  test('stats match the desktop counts', () async {
    final web = await facade.stats('c1');
    final desktop = await loadCharacterStats(db, 'c1');

    expect(web, desktop.toJson());
    expect(web!['theirWords'], 2);
    expect(web['yourMessages'], 1);
  });

  test('an unknown character has no stats', () async {
    expect(await facade.stats('nope'), isNull);
  });
}
