// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Widget tests for The Journal UI (docs/design/journal-memory.md §8 phase 3):
// - JournalPanel (sidebar peek): count, preview rows, pin marker, hidden when
//   the Journal is off, "Plant a memory" writes through to the store.
// - JournalDialog (full diary): category grouping, feeling lines (incl. the
//   "once felt X — now feels Y" healed arc), pin/retire persistence, faded
//   state, source-line receipts.
// - JournalCardEditorDialog: Save gated on non-empty content.
//
// Uses a REAL in-memory AppDatabase + JournalStore (the same pairing the
// journal unit tests exercise) under a FakeChatService that exposes them.

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/journal_ops.dart';
import 'package:front_porch_ai/services/chat/journal_review.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/journal_panel.dart';
import 'package:front_porch_ai/ui/dialogs/journal_card_editor.dart';
import 'package:front_porch_ai/ui/dialogs/journal_dialog.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

class _JournalChat extends FakeChatService {
  _JournalChat({required this.store, super.messages}) {
    journalReview = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
  }

  final JournalStore store;

  @override
  late final JournalReview journalReview;

  @override
  JournalStore get journalStore => store;

  @override
  String? get currentSessionId => 's1';
}

void main() {
  setupPathProviderMock();

  late AppDatabase db;
  late JournalStore store;
  late StorageService storage;
  late UserPersonaService persona;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // sameIsolate: the widgets await the store inside the fake-async test
    // zone — a background-isolate DB would deadlock (see forTesting doc).
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
    storage = StorageService();
    persona = UserPersonaService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedCard(
    String content, {
    String category = 'moment',
    String? emotion,
    String? intensity,
    List<int> positions = const [],
  }) => store.addCard(
    sessionId: 's1',
    characterId: 'mara',
    content: content,
    category: category,
    emotionLabel: emotion,
    emotionIntensity: intensity,
    sourcePositions: positions,
    maxCards: 200,
  );

  Widget wrap(_JournalChat chat, Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<StorageService>.value(value: storage),
      ChangeNotifierProvider<UserPersonaService>.value(value: persona),
    ],
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  Widget wrapPanel(_JournalChat chat, Widget panel) =>
      wrap(chat, SizedBox(width: 340, child: panel));

  // The diary dialog is 560×620 — give it room (default test surface is
  // 800×600 logical, which would overflow vertically).
  void sizeForDialog(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('JournalPanel', () {
    testWidgets('shows count, freshest preview rows, and the pin marker',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard('oldest memory');
      await seedCard('a pinned promise', category: 'promise');
      await seedCard('newer memory', emotion: 'wistful');
      await seedCard('newest memory', emotion: 'joyful');
      final pinTarget = (await store.cardsFor('s1', 'mara'))
          .firstWhere((c) => c.content == 'a pinned promise');
      await store.setPinned(pinTarget.id, true);

      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        wrapPanel(
          chat,
          JournalPanel(
            chatService: chat,
            characterId: 'mara',
            characterName: 'Mara',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The Journal'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // count badge
      // Preview = pinned first, then the freshest unpinned (3 rows total).
      expect(find.text('a pinned promise'), findsOneWidget);
      expect(find.text('newest memory'), findsOneWidget);
      expect(find.text('newer memory'), findsOneWidget);
      expect(find.text('oldest memory'), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      });
    });

    testWidgets('hidden entirely while the Journal is disabled',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await storage.setJournalEnabled(false);
      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        wrapPanel(
          chat,
          JournalPanel(
            chatService: chat,
            characterId: 'mara',
            characterName: 'Mara',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('The Journal'), findsNothing);
      });
    });

    testWidgets('plant a memory writes through to the store', (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      await tester.pumpWidget(
        wrapPanel(
          chat,
          JournalPanel(
            chatService: chat,
            characterId: 'mara',
            characterName: 'Mara',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plant a memory'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(
        find.byType(TextField).first,
        'He fixed the porch light without being asked.',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final cards = await store.cardsFor('s1', 'mara');
      expect(cards.single.content, 'He fixed the porch light without being asked.');
      expect(cards.single.category, 'moment');
      // The panel refreshed itself with the planted memory.
      await tester.pump();
      expect(
        find.text('He fixed the porch light without being asked.'),
        findsOneWidget,
      );
      });
    });
    testWidgets('pending review shows the banner and applying commits',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      chat.journalReview.park(
        JournalReviewBatch(
          sessionId: 's1',
          cursorTarget: 0,
          owners: [
            JournalOwnerProposals(
              ownerId: 'mara',
              ownerName: 'Mara',
              ops: [
                JournalProposedOp(
                  action: JournalOpAction.add,
                  text: 'A proposed memory.',
                ),
              ],
            ),
          ],
          recap: 'A proposed recap.',
        ),
      );
      sizeForDialog(tester);
      await tester.pumpWidget(
        wrapPanel(
          chat,
          JournalPanel(
            chatService: chat,
            characterId: 'mara',
            characterName: 'Mara',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('2 proposed update(s) — tap to review'),
        findsOneWidget,
      );
      await tester.tap(find.text('2 proposed update(s) — tap to review'));
      await tester.pumpAndSettle();

      expect(find.text('Proposed journal updates'), findsOneWidget);
      expect(find.text('A proposed memory.'), findsOneWidget);
      expect(find.text('A proposed recap.'), findsOneWidget);
      await tester.tap(find.text('Apply selected'));
      await tester.pumpAndSettle();

      expect(
        (await store.cardsFor('s1', 'mara')).single.content,
        'A proposed memory.',
      );
      expect(chat.journalReview.pending, isNull);
      // The banner is gone and the applied card shows in the preview.
      expect(find.textContaining('tap to review'), findsNothing);
      expect(find.text('A proposed memory.'), findsOneWidget);
      });
    });
  });

  group('JournalDialog', () {
    testWidgets('groups by category with feeling lines and the healed arc',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard(
        'Sam works nights at the hospital.',
        category: 'about_user',
        emotion: 'wistful',
        intensity: 'strong',
      );
      await seedCard('We watched the storm together.', category: 'about_us');
      final healed = (await store.cardsFor('s1', 'mara')).firstWhere(
        (c) => c.content == 'Sam works nights at the hospital.',
      );
      await store.reviseCard(healed, feeling: 'proud');

      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      sizeForDialog(tester);
      await tester.pumpWidget(
        wrap(
          chat,
          JournalDialog(chatService: chat, ownerId: 'mara', ownerName: 'Mara'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Mara's Journal"), findsOneWidget);
      expect(find.textContaining('2 memories from this chat'), findsOneWidget);
      // Friendly section labels: the user section carries the persona's
      // actual name; the raw category key never leaks into the UI.
      expect(
        find.text('About ${persona.persona.name}'.toUpperCase()),
        findsOneWidget,
      );
      expect(find.text('ABOUT_USER'), findsNothing);
      expect(find.text('ABOUT US'), findsOneWidget);
      expect(find.text('once felt wistful — now feels proud'), findsOneWidget);
      });
    });

    testWidgets('pin persists and retire (with confirm) deletes',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard('a memory to manage');
      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      sizeForDialog(tester);
      await tester.pumpWidget(
        wrap(
          chat,
          JournalDialog(chatService: chat, ownerId: 'mara', ownerName: 'Mara'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      expect((await store.cardsFor('s1', 'mara')).single.pinned, isTrue);
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retire'));
      await tester.pumpAndSettle();
      // Confirm dialog — the memory text is quoted, Retire commits.
      expect(find.text('Retire this memory?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retire'));
      await tester.pumpAndSettle();

      expect(await store.cardsFor('s1', 'mara'), isEmpty);
      expect(find.text('a memory to manage'), findsNothing);
      });
    });

    testWidgets('receipts show the cited chat lines', (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard('He apologized first.', positions: [0, 1]);
      final chat = _JournalChat(
        store: store,
        messages: [
          ChatMessage(text: 'I was wrong earlier.', sender: 'Sam', isUser: true),
          ChatMessage(text: 'That means a lot.', sender: 'Mara', isUser: false),
        ],
      );
      addTearDown(chat.dispose);
      sizeForDialog(tester);
      await tester.pumpWidget(
        wrap(
          chat,
          JournalDialog(chatService: chat, ownerId: 'mara', ownerName: 'Mara'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Where this came from'));
      await tester.pumpAndSettle();

      expect(find.text('Where this memory came from'), findsOneWidget);
      expect(find.textContaining('#0  Sam: I was wrong earlier.'), findsOneWidget);
      expect(find.textContaining('#1  Mara: That means a lot.'), findsOneWidget);
      // No jump callback wired here → no tap affordance offered.
      expect(find.text('Tap a line to go to it in the chat.'), findsNothing);
      });
    });

    testWidgets('tapping a receipt line closes the journal and jumps',
        (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard('He apologized first.', positions: [1]);
      final chat = _JournalChat(
        store: store,
        messages: [
          ChatMessage(text: 'I was wrong earlier.', sender: 'Sam', isUser: true),
          ChatMessage(text: 'That means a lot.', sender: 'Mara', isUser: false),
        ],
      );
      addTearDown(chat.dispose);
      sizeForDialog(tester);
      final jumps = <int>[];
      // Push the journal as a real dialog route so its self-pop on jump is
      // exercised (pumping it as `home` would pop the only route).
      await tester.pumpWidget(
        wrap(
          chat,
          Builder(
            builder: (ctx) => TextButton(
              onPressed: () => JournalDialog.show(
                ctx,
                chatService: chat,
                ownerId: 'mara',
                ownerName: 'Mara',
                onJumpToMessage: jumps.add,
              ),
              child: const Text('open journal'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open journal'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Where this came from'));
      await tester.pumpAndSettle();
      expect(find.text('Tap a line to go to it in the chat.'), findsOneWidget);

      await tester.tap(find.textContaining('#1  Mara: That means a lot.'));
      await tester.pumpAndSettle();

      expect(jumps, [1]);
      // Both the receipts and the journal itself closed — the chat behind
      // them is what the jump scrolls.
      expect(find.text("Mara's Journal"), findsNothing);
      expect(find.text('Where this memory came from'), findsNothing);
      });
    });

    testWidgets('a cold card renders faded', (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await seedCard('an old faded memory');
      final card = (await store.cardsFor('s1', 'mara')).single;
      await db.updateJournalCard(
        card.id,
        const JournalMemoriesCompanion(heat: drift.Value(0.1)),
      );

      final chat = _JournalChat(store: store);
      addTearDown(chat.dispose);
      sizeForDialog(tester);
      await tester.pumpWidget(
        wrap(
          chat,
          JournalDialog(chatService: chat, ownerId: 'mara', ownerName: 'Mara'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('faded'), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
      });
    });
  });

  group('JournalCardEditorDialog', () {
    testWidgets('Save is gated on non-empty content', (tester) async {
      // Real-async escape: drift parks on real timers the fake-async
      // zone never fires; runAsync runs the real event loop instead.
      await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: JournalCardEditorDialog(
              title: 'Plant a memory',
              userName: 'Sam',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      FilledButton save() =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
      expect(save().onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'A real memory.');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      });
    });
  });
}
