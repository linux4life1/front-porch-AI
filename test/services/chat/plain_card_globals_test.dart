// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// A PLAIN IMPORTED CARD MUST STILL GET THE GLOBAL DEFAULTS.
//
// The seed block in `setActiveCharacter` used to run only
// `if (_activeCharacter!.frontPorchExtensions != null)`, while the comment
// three lines inside it explains that the OR-override exists
//
//     "to force realism ON for imported cards (Chub/V2 PNG/BYAF) that carry
//      no realism setup, so the engine reads the room + generates baselines
//      without the user editing every card"
//
// A card that carries no realism setup has NO extensions object at all. So the
// guard excluded precisely the population the code inside it was written to
// serve: every plain PNG downloaded from Chub or exported from another app fell
// straight through and received none of the globals — not the Realism default,
// not Afterglow, not Needs, and (2026-08-08) not the new Chaos default. Switch
// a global on, open a card you just downloaded, and nothing happens, with
// nothing on screen to explain why.
//
// The fix reads a default-constructed FrontPorchExtensions when the card has
// none. The CARD is not mutated — a plain PNG stays plain on disk and on The
// Stoop — so this is a read-side default only.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    // Awaited, never slept on: `_init()` ends by re-reading every setting from
    // SharedPreferences, so a value set before it lands is silently discarded.
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await db.close();
  });

  /// Exactly what a Chub / V2 PNG import produces: name, greeting, prose, and
  /// no `frontPorchExtensions` whatsoever.
  CharacterCard plain(String id) =>
      CharacterCard(name: 'Imported', firstMessage: 'Evening.')..dbId = id;

  test('the global Chaos default reaches a plain imported card', () async {
    await storage.realismSettings.setChaosModeDefault(true);

    await chat.setActiveCharacter(plain('plain-chaos'));

    expect(
      chat.chaosModeService.chaosModeEnabled,
      isTrue,
      reason:
          'the guard skipped every card with no extensions — which is '
          'every plain import, the exact population the OR-override exists for',
    );
  });

  test('the global Realism default reaches one too', () async {
    // The oldest of these overrides, and the one whose comment names imported
    // cards outright. It was the most broken by the guard.
    await storage.realismSettings.setRealismDefault(true);

    await chat.setActiveCharacter(plain('plain-realism'));

    expect(chat.realismEnabled, isTrue);
  });

  test('a card that DOES carry extensions is unchanged', () async {
    // The fix must be a read-side default and nothing more. A card with its
    // own realism section keeps deciding for itself, exactly as before.
    await storage.realismSettings.setChaosModeDefault(false);

    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Authored',
        firstMessage: 'Hi.',
        frontPorchExtensions: FrontPorchExtensions(chaosModeEnabled: true),
      )..dbId = 'authored',
    );

    expect(
      chat.chaosModeService.chaosModeEnabled,
      isTrue,
      reason:
          'the card asked for Chaos; the global being off must not veto it '
          '— this is an OR-override, not an AND-gate',
    );
  });

  test('globals off leave a plain card alone', () async {
    // The other direction: the default-constructed extensions must not smuggle
    // anything ON. Every field it supplies is the same value an empty realism
    // section would have.
    await chat.setActiveCharacter(plain('plain-off'));

    expect(chat.chaosModeService.chaosModeEnabled, isFalse);
    expect(chat.realismEnabled, isFalse);
  });

  test('the card itself is not given an extensions object', () async {
    // Read-side only. Writing one would change the card's JSON shape, which
    // ripples to the PNG, The Stoop and every external reader — and would
    // quietly convert a user's whole library of plain imports.
    final card = plain('plain-untouched');
    await chat.setActiveCharacter(card);

    expect(card.frontPorchExtensions, isNull);
  });
}
