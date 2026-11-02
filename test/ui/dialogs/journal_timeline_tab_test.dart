// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Journal dialog's "Our Story" tab reads newest first (issue #690):
// day headers count down from the latest, and the newest moment sits on top.
// Real in-memory AppDatabase + MilestoneFeed under a FakeChatService.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/milestone_feed.dart';
import 'package:front_porch_ai/ui/dialogs/journal_timeline_tab.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _TimelineChat extends FakeChatService {
  _TimelineChat({required this.feed});

  final MilestoneFeed feed;

  @override
  MilestoneFeed get milestoneFeed => feed;

  @override
  String? get currentSessionId => 's1';
}

void main() {
  setupPathProviderMock();

  late AppDatabase db;
  late JournalStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // sameIsolate: the widget awaits the DB inside the fake-async test zone.
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed(String content, {required int day, required int pos}) =>
      store.addCard(
        sessionId: 's1',
        characterId: 'mara',
        content: content,
        category: 'moment',
        emotionIntensity: 'strong',
        sourcePositions: [pos],
        storyDay: day,
        maxCards: 200,
      );

  testWidgets('Our Story counts the days down from the latest', (tester) async {
    // Real-async escape: drift parks on real timers the fake-async zone
    // never fires; runAsync runs the real event loop instead.
    await tester.runAsync(() async {
      await seed('First porch evening.', day: 1, pos: 0);
      await seed('The night of the storm.', day: 3, pos: 4);

      final chat = _TimelineChat(
        feed: MilestoneFeed(getDb: () => db, getMessages: () => const []),
      );
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: JournalTimelineTab(chat: chat, ownerId: 'mara'),
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
    });
  });
}
