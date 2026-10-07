// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Scene Guest's reply is a beat on the shared story clock, so the 1:1
// host's refractory runs down by it even though the host did not speak — and
// it does not spend the host's opening afterglow turn. Regen, swipe and a
// tail delete of the guest's reply put the host where that beat found or
// left them.
//
// Red proofs, each run with the named piece taken out:
//  * the guest beat: `_tickRefractoryAfterClock(t)` in the lite finalize;
//  * guest regen: the receipt restore in the guest branch of
//    `_revertRegenRealismBaseline`;
//  * swipe: `_restoreRefractoryAfterBeat` in `_restoreWornBodiesExceptSpeaker`;
//  * tail delete: the `_restoreRefractoryBeforeBeat` line in deleteMessage.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_refr_guest_').path;
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
  late RefractoryJudges llm;
  DebugPrintCallback? previousPrint;

  Future<void> settle() async {
    for (
      var i = 0;
      i < 500 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {};
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = RefractoryJudges();
    final repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    final host = CharacterCard(
      name: 'Flora',
      firstMessage: 'Evening.',
      imagePath: 'refr-flora.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
      ),
    );
    final guest = CharacterCard(
      name: 'Riley',
      firstMessage: 'Hi.',
      imagePath: 'refr-riley.png',
      frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
    );
    await repo.addCharacter(host);
    await repo.addCharacter(guest);
    await chat.setActiveCharacter(host);
    await chat.setRealismEnabled(true);
    await chat.setNsfwCooldownEnabled(true);
    await chat.joinSceneGuest(guest);
    await settle();

    // The host climaxes in her own reply: 75 minutes, opening turn unspoken.
    llm
      ..minutes = 5
      ..climax = true
      ..refractoryTurns = 5;
    await chat.sendMessage('The wave crests and breaks over us both.');
    await settle();
    llm.climax = false;
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  CharacterCard liveGuest() =>
      chat.sceneGuestCards.firstWhere((c) => c.name == 'Riley');

  int hostMinutes() => chat.nsfwService.refractoryMinutesRemaining;

  Future<void> guestSpeaks(int minutes) async {
    llm.minutes = minutes;
    await chat.speakGuestNow(liveGuest());
    await settle();
    expect(chat.messages.last.sender, 'Riley', reason: 'baseline: guest beat');
  }

  test('a guest\'s beat runs the host\'s refractory down and leaves her '
      'opening turn unspoken', () async {
    expect(chat.messages.last.sender, 'Flora', reason: 'baseline: no chime-in');
    expect(hostMinutes(), 75);

    await guestSpeaks(30);
    expect(hostMinutes(), 45, reason: 'the clock moved for everyone present');
    expect(
      chat.nsfwService.isOpeningAfterglowTurn,
      isTrue,
      reason: 'the host has not spoken since her climax',
    );
  });

  test('regen, swipe and tail delete of the guest\'s reply move the host '
      'with that beat', () async {
    await guestSpeaks(30);
    expect(hostMinutes(), 45);

    llm.minutes = 10;
    await chat.regenerateLastMessage();
    await settle();
    expect(
      hostMinutes(),
      65,
      reason: '75 restored before the replay, then its 10-minute beat once',
    );

    final idx = chat.messages.length - 1;
    await chat.swipeMessage(idx, -1);
    await settle();
    expect(hostMinutes(), 45, reason: 'the first alternative left her at 45');
    await chat.swipeMessage(idx, 1);
    await settle();
    expect(hostMinutes(), 65);

    // A second guest beat, then delete it. The reply left at the tail is the
    // guest's, which carries no snapshot of the host, so only the deleted
    // beat's own record can give her the minutes back.
    await guestSpeaks(20);
    expect(hostMinutes(), 45);
    chat.deleteMessage(chat.messages.length - 1);
    await settle();
    expect(
      hostMinutes(),
      65,
      reason: 'the deleted beat gives its minutes back',
    );
  });
}
