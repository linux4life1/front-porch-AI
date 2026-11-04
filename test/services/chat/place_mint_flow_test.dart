import 'dart:io';

// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7: the chat-side mint seam contract (chat_service_wiring_mint).
// The seams hold, answer, and forget; they never throw into the chat
// loop and never leave a half-state. The live transport ride is pinned
// by the integration mint journey, not here.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setupPath() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.createTempSync('fpai_mintflow_').path;
          }
          return null;
        });
  }

  late ChatService chat;
  late AppDatabase db;
  late StorageService storage;
  late WorldRepository worlds;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setupPath();
    storage = StorageService();
    await storage.initialized;
    db = AppDatabase.forTesting();
    worlds = WorldRepository(storage, db);
    await worlds.ready;
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      worlds,
    )..setDatabase(db);
  });

  tearDown(() => db.close());

  test('the seam flags a proposal and reads it back verbatim', () {
    expect(chat.pendingPlaceMint, isNull);
    chat.flagSuggestedPlaceMint('The Salt Garden', 'hedged beds');
    expect(chat.pendingPlaceMint?.name, 'The Salt Garden');
    expect(chat.pendingPlaceMint?.descriptor, 'hedged beds');
  });

  test('a blank name is never worth a dialog', () {
    chat.flagSuggestedPlaceMint('   ', 'x');
    expect(chat.pendingPlaceMint, isNull);
  });

  test(
    'Ignore clears the proposal and remembers the name for the chat',
    () async {
      chat.flagSuggestedPlaceMint('Salt Garden', 'beds');
      chat.ignoreMintedPlace();
      expect(chat.pendingPlaceMint, isNull);
      // The flagging lambda in the clock wiring consults this set; a
      // re-proposal of the SAME name is what the dialog must stop seeing.
      chat.flagSuggestedPlaceMint('Gate House', 'arch');
      expect(chat.pendingPlaceMint?.name, 'Gate House');
    },
  );

  test('the proposal names the current setting for the dialog copy', () {
    // The web modal must be able to say "inside <world>" verbatim like
    // the desktop dialog (review #607 copy parity) — the flag carries
    // it, not the UI guessing from another fetch.
    chat.flagSuggestedPlaceMint('Salt Garden', 'beds');
    expect(
      chat.pendingPlaceMint?.settingName,
      '',
      reason: 'no setting attached → empty, dialog drops the clause',
    );
  });

  test(
    'accepting with no setting fails honestly — no throw, no residue',
    () async {
      chat.flagSuggestedPlaceMint('Salt Garden', 'beds');
      final result = await chat.acceptMintedPlace(alsoMove: false);
      expect(result.ok, isFalse);
      expect(result.error, contains('no setting'));
      expect(chat.pendingPlaceMint, isNull, reason: 'a refusal must not nag');
    },
  );

  test('answering when nothing is proposed is an honest no-op', () async {
    final r = await chat.acceptMintedPlace(alsoMove: true);
    expect(r.ok, isFalse);
    expect(r.error, contains('nothing is being proposed'));
    chat.ignoreMintedPlace(); // must not throw
  });

  group('a mint never re-mints an existing place', () {
    Future<model.World> seedPlace(String name, {String? parent}) async {
      final w = model.World(
        name: name,
        description: 'A room that already exists.',
        lorebook: Lorebook(entries: []),
        parentWorldId: parent,
      );
      await worlds.saveWorld(w);
      return w;
    }

    test(
      'a name the library already holds rides the MOVE offer, not a mint',
      () async {
        final warmward = await seedPlace('Warmward Guest Chamber');
        chat.flagSuggestedPlaceMint('Warmward Guest Chamber', 'a duplicate');
        expect(
          chat.pendingPlaceMint,
          isNull,
          reason: 'the mint dialog must never offer a second copy',
        );
        expect(
          chat.pendingPlaceMove?.id,
          warmward.id,
          reason: 'the arrival becomes a move to the place that exists',
        );
        expect(chat.pendingPlaceMove?.name, 'Warmward Guest Chamber');
      },
    );

    test('the match is trimmed and case-insensitive', () async {
      final warmward = await seedPlace('Warmward Guest Chamber');
      chat.flagSuggestedPlaceMint('  warmward  GUEST chamber ', 'x');
      expect(chat.pendingPlaceMint, isNull);
      expect(chat.pendingPlaceMove?.id, warmward.id);
    });

    test('an unknown name still flags a mint untouched', () async {
      await seedPlace('Warmward Guest Chamber');
      chat.flagSuggestedPlaceMint('The Salt Garden', 'hedged beds');
      expect(chat.pendingPlaceMint?.name, 'The Salt Garden');
      expect(chat.pendingPlaceMove, isNull);
    });

    test(
      'a moved-to name that exists can never also be minted from it',
      () async {
        // The move redirect means the mint pending can only ever carry a
        // name the library did NOT hold at flag time; a later clash is
        // then refused inside PlaceFactory (pinned in place_factory_test).
        // Here: after the redirect, nothing mint-able lingers.
        await seedPlace('Warmward Guest Chamber');
        chat.flagSuggestedPlaceMint('Warmward Guest Chamber', 'x');
        expect(chat.pendingPlaceMint, isNull);
        final r = await chat.acceptMintedPlace(alsoMove: false);
        expect(r.error, contains('nothing is being proposed'));
      },
    );
  });
}
