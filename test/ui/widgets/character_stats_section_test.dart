// The "Your chats together" card on the character Details tab: it shows the
// real counts from the library, and stays out of the way for a character you
// have never chatted with.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  // Without a loader the section reads the library itself. It opened the
  // startup singleton (AppDatabase.instance), whose first open reads
  // SharedPreferences and the documents folder: in a test that is no
  // database at all, and on CI its failure surfaced as an uncaught error in
  // whichever test was running. It reads the database the page has.
  Future<void> pumpFromLibrary(WidgetTester tester, {AppDatabase? database}) {
    final section = MaterialApp(
      home: Scaffold(
        body: CharacterStatsSection(
          characterId: 'mira',
          wrap: (content) =>
              Column(children: [const Text('Your chats together'), content]),
        ),
      ),
    );
    return tester.pumpWidget(
      database == null
          ? section
          : Provider<AppDatabase>.value(value: database, child: section),
    );
  }

  testWidgets("without a loader it counts from the page's database", (
    tester,
  ) async {
    await tester.runAsync(() async {
      await db.insertSession(
        SessionsCompanion.insert(id: 's', characterId: const Value('mira')),
      );
      await db
          .into(db.messages)
          .insert(
            MessagesCompanion.insert(
              id: 'm0',
              sessionId: 's',
              position: 0,
              sender: 'Mira',
              isUser: false,
              swipes: Value(jsonEncode(['Evening'])),
            ),
          );
      await pumpFromLibrary(tester, database: db);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('Your chats together'), findsOneWidget);
    expect(find.text('Their messages'), findsOneWidget);
  });

  testWidgets('a library read that fails is logged and leaves the section '
      'empty, and never reaches the platform', (tester) async {
    final logged = <String>[];
    final print = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      logged.add(message ?? '');
      print(message, wrapWidth: wrapWidth);
    };
    // The singleton's first open asks these channels; the page's database
    // needs neither. Each call is counted and left unanswered.
    const channels = [
      'plugins.flutter.io/shared_preferences',
      'plugins.flutter.io/path_provider',
    ];
    final calls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final channel in channels) {
      messenger.setMockMessageHandler(channel, (message) async {
        calls.add(channel);
        return null;
      });
    }
    // No database above it: the read throws.
    await tester.runAsync(() async {
      await pumpFromLibrary(tester);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    for (final channel in channels) {
      messenger.setMockMessageHandler(channel, null);
    }
    debugPrint = print; // the binding checks it is back before the test ends

    expect(calls, isEmpty, reason: 'the section opened the startup singleton');
    expect(tester.takeException(), isNull);
    expect(find.byType(CharacterStatsSection), findsOneWidget);
    expect(find.text('Your chats together'), findsNothing);
    expect(
      logged.where((l) => l.startsWith('[character stats] load failed')),
      hasLength(1),
      reason: 'a failed read is said, not swallowed',
    );
  });
}
