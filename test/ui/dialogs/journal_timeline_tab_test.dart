// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Our Story" reads newest first on both surfaces (issue #690): the desktop
// Journal dialog's timeline tab and the web timeline the facade serves. Day
// headers count down from the latest, and an entry with no story day of its
// own (a Chance Time strike, a ring) stays under the day it happened on.
// Real in-memory AppDatabase + MilestoneFeed under a FakeChatService.
//
// Its own file because the test needs a fake that overrides milestoneFeed,
// and appending a new fake class to journal_ui_test.dart trips the
// protected-paths guard.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/milestone_feed.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/ui/dialogs/journal_timeline_tab.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _TimelineChat extends FakeChatService {
  _TimelineChat({required this.feed, required this.owner});

  final MilestoneFeed feed;
  final ChatParticipant owner;

  @override
  MilestoneFeed get milestoneFeed => feed;

  @override
  String? get currentSessionId => 's1';

  @override
  List<ChatParticipant> get cast => [owner];
}

void main() {
  setupPathProviderMock();

  late AppDatabase db;
  late JournalStore store;
  late _TimelineChat chat;
  late ChatParticipant owner;

  // A Chance Time strike at message #3 sits between the Day 1 card (#1) and
  // the Day 3 card (#5) and carries no story day of its own.
  final messages = [
    for (var i = 0; i < 5; i++)
      i == 2
          ? ChatMessage(
              text: '[🎰 CHANCE TIME! A stranger knocks.]',
              sender: 'System',
              isUser: false,
              metadata: {'is_chance_time_narration': true},
            )
          : ChatMessage(text: 'line $i', sender: 'User', isUser: true),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // sameIsolate: the widget awaits the DB inside the fake-async test zone.
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
    owner = ChatParticipant(
      card: CharacterCard(name: 'Mara', imagePath: '/tmp/mara.png'),
      isHost: true,
    );
    chat = _TimelineChat(
      feed: MilestoneFeed(getDb: () => db, getMessages: () => messages),
      owner: owner,
    );
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  Future<void> seed(String content, {required int day, required int pos}) =>
      store.addCard(
        sessionId: 's1',
        characterId: owner.id,
        content: content,
        category: 'moment',
        emotionIntensity: 'strong',
        sourcePositions: [pos],
        storyDay: day,
        maxCards: 200,
      );

  testWidgets('desktop Our Story counts the days down from the latest', (
    tester,
  ) async {
    // Real-async escape: drift parks on real timers the fake-async zone
    // never fires; runAsync runs the real event loop instead.
    await tester.runAsync(() async {
      await seed('First porch evening.', day: 1, pos: 0);
      await seed('The night of the storm.', day: 3, pos: 4);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: JournalTimelineTab(chat: chat, ownerId: owner.id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Day 3'), lessThan(top('Day 1')));
      expect(
        top('The night of the storm.'),
        lessThan(top('First porch evening.')),
      );
      // The Day 1 strike stays under Day 1, below its header, not Day 3's.
      expect(top('A stranger knocks.'), greaterThan(top('Day 1')));
    });
  });

  test(
    'the web timeline is newest first and keeps each entry on its day',
    () async {
      await seed('First porch evening.', day: 1, pos: 0);
      await seed('The night of the storm.', day: 3, pos: 4);

      final facade = ChatToolsFacade(chat, StorageService(), null);
      final body = await facade.timeline(null);
      final entries = (body['entries'] as List).cast<Map<String, dynamic>>();
      expect(entries.map((e) => (e['text'], e['day'])), [
        ('The night of the storm.', 3),
        ('A stranger knocks.', 1),
        ('First porch evening.', 1),
      ]);
    },
  );
}
