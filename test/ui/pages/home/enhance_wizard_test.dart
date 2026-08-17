// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The AI Enhance WIZARD (2026-08-13 maintainer-directed rework: the old
// EnhanceSetupPage + options dialog chain became a creator-style stepper —
// About → Model → Chat → Interview → Review → Chats — so the feature
// explains itself instead of assuming users "just know"). This suite
// replaces enhance_setup_page_test.dart, whose subject page was deleted;
// its contract (hosts the creator's REAL SetupStep, Continue gated on an
// actually-ready backend) is re-pinned here at the wizard's Model step.
//
// New route + multi-step navigation → interaction test per the routes rule.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart' hide World;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_wizard_page.dart';

import '../../../golden/support/fakes_services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          final tmp = Directory.systemTemp.createTempSync('fpai_test_');
          return tmp.path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Bounded settle: the REAL SetupStep runs repeating animations (blinking
  // backend status dot), which makes pumpAndSettle spin forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Real-async escape for service init + DB seeding (repo convention).
  Future<
    ({
      StorageService storage,
      KoboldService kobold,
      BackendManager backendManager,
      LLMProvider llm,
      AppDatabase db,
      CharacterRepository repo,
      ChatService chat,
    })
  >
  buildServices(WidgetTester tester) async {
    late final StorageService storage;
    late final KoboldService kobold;
    late final BackendManager backendManager;
    late final LLMProvider llm;
    late final AppDatabase db;
    late final CharacterRepository repo;
    late final ChatService chat;
    await tester.runAsync(() async {
      storage = StorageService();
      await storage.initialized;
      // Remote backend, configured + keyed → ready without a local process.
      await storage.setBackendType('openRouter');
      await storage.setRemoteModel('current/model');
      await storage.setRemoteApiKey('test-key');
      kobold = KoboldService(storage);
      backendManager = BackendManager(storage);
      llm = LLMProvider(kobold, OpenRouterService(), storage, backendManager);
      // Same-isolate DB — a background-isolate DB deadlocks the fake-async
      // test zone (see the AppDatabase.forTesting doc).
      db = AppDatabase.forTesting(sameIsolate: true);
      repo = CharacterRepository(db, storage);
      chat =
          ChatService(kobold, UserPersonaService(db), storage,
              WorldRepository(storage, db))
            ..setDatabase(db)
            ..setCharacterRepository(repo);
    });
    return (
      storage: storage,
      kobold: kobold,
      backendManager: backendManager,
      llm: llm,
      db: db,
      repo: repo,
      chat: chat,
    );
  }

  Widget wrap(dynamic s, CharacterCard card) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: s.storage),
        ChangeNotifierProvider<KoboldService>.value(value: s.kobold),
        ChangeNotifierProvider<BackendManager>.value(value: s.backendManager),
        ChangeNotifierProvider<LLMProvider>.value(value: s.llm),
        ChangeNotifierProvider<ModelManager>.value(value: FakeModelManager()),
        ChangeNotifierProvider<ChatService>.value(value: s.chat),
        Provider<AppDatabase>.value(value: s.db),
      ],
      child: MaterialApp(home: EnhanceWizardPage(character: card)),
    );
  }

  testWidgets(
      'About step explains the feature; zero chats disables Next with a '
      '"have a chat first" callout', (tester) async {
    _setupPathProviderMock();
    SharedPreferences.setMockInitialValues({});
    final s = await buildServices(tester);
    // No PNG / not in the repo → getSessionsForId resolves nothing.
    final card = CharacterCard(name: 'Nina', description: 'desc');

    await tester.pumpWidget(wrap(s, card));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await settle(tester);

    // The explainer is the whole point of step 0.
    expect(find.text('What is AI Enhance?'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('You review everything'), findsOneWidget);
    expect(find.textContaining('Have a chat with Nina first'), findsOneWidget);

    final next = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Next: Model'),
    );
    expect(next.onPressed, isNull,
        reason: 'no chats → the wizard cannot proceed past About');
  });

  testWidgets(
      'walks About → Model (real SetupStep, ready-gated) → Chat → Interview '
      'checklist', (tester) async {
    _setupPathProviderMock();
    SharedPreferences.setMockInitialValues({});
    final s = await buildServices(tester);

    late final CharacterCard card;
    await tester.runAsync(() async {
      card = CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the enhance-wizard test.',
        firstMessage: 'The porch light hums.',
      );
      final tmpDir = Directory.systemTemp.createTempSync('enw_card_');
      final pngPath = '${tmpDir.path}/Mara.png';
      await V2CardService().saveCardAsPng(card, pngPath, null);
      card.imagePath = pngPath;
      await s.repo.addCharacter(card);
      await s.db.insertSession(
        SessionsCompanion.insert(
          id: '1700000000001',
          characterId: Value(card.dbId),
        ),
      );
      for (final (i, line) in ['Hello there.', 'Hi yourself.'].indexed) {
        await s.db.insertMessage(
          MessagesCompanion.insert(
            id: 'sess-m$i',
            sessionId: '1700000000001',
            position: i,
            sender: i.isEven ? 'You' : card.name,
            isUser: i.isEven,
            swipes: Value('["$line"]'),
          ),
        );
      }
    });

    await tester.pumpWidget(wrap(s, card));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await settle(tester);

    // About: the chat was found, Next is live.
    expect(find.textContaining('1 chat to learn from'), findsOneWidget);
    await tester.tap(find.text('Next: Model'));
    await settle(tester);

    // Model: the creator's REAL step (full picker was a maintainer
    // requirement; a cut-down row was rejected), Continue gated on an
    // actually ready backend — remote is configured + keyed, so it's live.
    expect(find.byType(SetupStep), findsOneWidget);
    expect(find.text('Backend & Model Setup'), findsOneWidget);
    expect(find.text('KoboldCpp (Local)'), findsOneWidget);
    await tester.tap(find.text('Next: Chat'));
    await settle(tester);

    // Chat: the single session is listed and auto-selected.
    expect(find.textContaining('already selected'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.tap(find.text('Next: Interview'));
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 100)));
    await settle(tester);

    // Interview: checklist with the persona trio + 18+ toggle; one user
    // turn → the short-chat warning; the run button is armed.
    expect(find.text('What should the interview rewrite?'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Personality'), findsOneWidget);
    expect(
      find.text('Porch Life (wardrobe, ambitions, likes)'),
      findsOneWidget,
    );
    expect(find.text('Allow 18+ themes'), findsOneWidget);
    expect(find.textContaining('very short'), findsOneWidget);
    expect(find.text('Start the Interview'), findsOneWidget);

    // Back returns to the Chat step — linear progression both ways.
    await tester.tap(find.text('Back'));
    await settle(tester);
    expect(find.textContaining('already selected'), findsOneWidget);

    await tester.runAsync(() async {
      s.chat.dispose();
      await s.db.close();
    });
  });
}
