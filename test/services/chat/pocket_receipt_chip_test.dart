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

// THE WARDROBE RECEIPT HAS TO BE ON THE MAP THE BUBBLE READS.
//
// A generated message carries TWO metadata maps that start out as one object:
// `metadata` (the shared base) and `swipeMetadata[i]` (this variant). The
// bubble renders `activeMetadata`, which prefers `swipeMetadata[i]` the moment
// it is non-null — and it is non-null on every turn where Realism or Needs
// attached anything, i.e. most turns for most users.
//
// The pockets pass used to write its receipts by REPLACING the base map
// (`msg.metadata = {...}`), which both breaks the alias and puts the receipts
// on the map nobody displays. It then rebuilt the swipe map from the stale
// pre-receipt copy, so "picked up: car keys" was written and immediately
// overwritten out of view — the chip never appeared, on this turn or after a
// reload, and the regen swipe-merge (which copies activeMetadata) dropped it
// too. With Realism OFF the same code accidentally worked, which is why it
// survived: the feature looked fine exactly where nobody was looking.
//
// Proven to fail first: writing `pocket_changes` back onto `msg.metadata`
// instead of into the after/active map turns the first test red
// (`pocket_changes` reads null) while the second stays green.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_pchip_').path;
        }
        return null;
      });
}

/// Answers the conversational turn, and answers the pockets pass with one
/// pickup so the pass has a receipt to attach. Every other eval gets an empty
/// string, which every one of them treats as "nothing to apply".
class _ScriptedLlm extends LLMService {
  int pocketsCalls = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      yield '*She scoops the car keys off the rail.*';
      return;
    }
    if (params.prompt.contains('inventory_ops')) {
      pocketsCalls++;
      yield '{"inventory_ops":[{"op":"pickup","item":"car keys"}]}';
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  Future<void> boot({required bool realism}) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': realism,
      'pockets_enabled': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  }

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainTurn() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  CharacterCard card(bool realism) => CharacterCard(
    name: 'Mara',
    description: 'Exists only inside the pocket-receipt test.',
    firstMessage: 'The porch light hums.',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: realism,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = 'char-pchip-1';

  Future<List<String>> receiptsOnLastReply() async {
    await chat.sendMessage('What did you just pick up?');
    await drainTurn();
    final last = chat.messages.last;
    expect(llm.pocketsCalls, greaterThan(0), reason: 'the pass must have run');
    final chips = last.activeMetadata?['pocket_changes'];
    return chips is List ? chips.whereType<String>().toList() : const [];
  }

  test('with Realism ON — the case that was broken — the chip is on the map '
      'the bubble reads', () async {
    await boot(realism: true);
    await chat.setActiveCharacter(card(true));

    expect(
      await receiptsOnLastReply(),
      ['picked up: car keys'],
      reason:
          'message_bubble renders activeMetadata; a receipt parked on the '
          'shared base map is invisible once this swipe has its own map',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('with Realism OFF the chip is still there (no regression on the path '
      'that accidentally worked)', () async {
    await boot(realism: false);
    await chat.setActiveCharacter(card(false));

    expect(await receiptsOnLastReply(), ['picked up: car keys']);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
