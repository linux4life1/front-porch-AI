// Character stats count what was actually said in a character's 1:1 chats:
// the swipe on screen, without thinking, without deleted chats or messages,
// director notes or other characters' chats.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_stats.dart';

void main() {
  late AppDatabase db;
  var pos = 0;

  setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
  tearDown(() async => db.close());

  Future<void> chat(String id, String charId, {DateTime? at}) =>
      db.insertSession(
        SessionsCompanion.insert(
          id: id,
          characterId: Value(charId),
          createdAt: at == null ? const Value.absent() : Value(at),
          updatedAt: at == null ? const Value.absent() : Value(at),
        ),
      );

  Future<void> say(
    String sessionId,
    bool isUser,
    List<String> swipes, {
    int swipeIndex = 0,
    String? characterId,
    bool deleted = false,
  }) => db
      .into(db.messages)
      .insert(
        MessagesCompanion.insert(
          id: 'm${pos++}',
          sessionId: sessionId,
          position: pos,
          sender: isUser ? 'You' : 'Mira',
          isUser: isUser,
          characterId: Value(characterId),
          swipes: Value(jsonEncode(swipes)),
          swipeIndex: Value(swipeIndex),
          deletedAt: deleted ? Value(DateTime(2026)) : const Value.absent(),
        ),
      );

  test('counts the shown swipe of live messages in live 1:1 chats', () async {
    final first = DateTime(2026, 3, 1);
    final last = DateTime(2026, 9, 2);
    await chat('a', 'mira', at: first);
    await chat('b', 'mira', at: last);
    await chat('other', 'someone-else');

    await say('a', false, ['Hello there friend']);
    await say('a', true, ['Hi']);
    await say('a', false, [
      'one two',
      '<think>plan the reply</think>three four five',
    ], swipeIndex: 1);
    await say('a', false, ['*Director note*'], characterId: '__director__');
    await say('a', true, ['gone now'], deleted: true);
    await say('a', false, ['']);
    await say('b', true, ['Back again']);
    await say('other', true, ['not hers at all']);

    final stats = await loadCharacterStats(db, 'mira');

    expect(stats.chats, 2);
    expect(stats.theirMessages, 2);
    expect(stats.yourMessages, 2);
    expect(stats.theirWords, 6);
    expect(stats.yourWords, 3);
    expect(stats.longestChat, 3);
    expect(stats.firstChat, first);
    expect(stats.lastChat, last);
  });

  test('a deleted chat does not count', () async {
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'old',
        characterId: const Value('mira'),
        deletedAt: Value(DateTime(2026)),
      ),
    );
    await say('old', true, ['Hello']);

    final stats = await loadCharacterStats(db, 'mira');

    expect(stats.chats, 0);
    expect(stats.isEmpty, isTrue);
  });
}
