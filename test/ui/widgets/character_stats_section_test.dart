// The "Your chats together" card on the character Details tab: it shows the
// real counts from the library, and stays out of the way for a character you
// have never chatted with.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/character_stats.dart';
import 'package:front_porch_ai/ui/widgets/character_stats_section.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(sameIsolate: true));
  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, String id) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CharacterStatsSection(
              characterId: id,
              load: (id) => loadCharacterStats(db, id),
              wrap: (content) => Column(
                children: [const Text('Your chats together'), content],
              ),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  testWidgets('shows the counts for a character you have chatted with', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.insertSession(
        SessionsCompanion.insert(id: 's', characterId: const Value('mira')),
      );
      var pos = 0;
      for (final (isUser, text) in [
        (false, 'Evening on the porch'),
        (true, 'Hey Mira'),
        (false, 'Sit down'),
      ]) {
        await db
            .into(db.messages)
            .insert(
              MessagesCompanion.insert(
                id: 'm$pos',
                sessionId: 's',
                position: pos++,
                sender: isUser ? 'You' : 'Mira',
                isUser: isUser,
                swipes: Value(jsonEncode([text])),
              ),
            );
      }
    });

    await pump(tester, 'mira');

    expect(find.text('Your chats together'), findsOneWidget);
    expect(find.text('Their messages'), findsOneWidget);
    final theirWordsTile = find
        .ancestor(of: find.text('Their words'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: theirWordsTile, matching: find.text('6')),
      findsOneWidget,
    );
    expect(find.text('3 messages'), findsOneWidget);
  });

  testWidgets('shows nothing for a character you have never chatted with', (
    tester,
  ) async {
    await pump(tester, 'nobody');

    expect(find.text('Your chats together'), findsNothing);
    expect(find.text('Chats'), findsNothing);
  });
}
