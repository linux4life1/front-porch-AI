// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The refractory counts story minutes (needs-on-the-clock v2, "Refractory on
// the clock"), driven through real 1:1 turns. The scripted backend only
// answers the judges' questions (how many minutes passed, did she climax and
// how many turns); every number asserted here is computed by the product.
//
// Red proofs, each run with the named piece taken out:
//  * 20-minute beat: the engine's `_tickRefractoryAfterClock(t)` line.
//  * two-hour skip / next morning: the beat measured from this reply's own
//    `story_clock_before` instead of the earlier reply's after (a send-time
//    skip is stamped before that before).
//  * opening turn: the post-gen markOpened step.
//  * Continue: the `t.mode != GenerationMode.normal` gate in
//    `_tickRefractoryAfterClock` (without it Continue re-charges the beat).
//  * regen (clock on): the post-gen restamp of the minutes and the flag into
//    the reply's realism_state, which the regen merge restores. (Here the
//    previous reply's snapshot already rewinds the host, so the receipt
//    restore in `_revertRegenRealismBaseline` is proven by the group suite.)
//  * regen (clock off): the reprocess per-reply tick.
//  * tail delete: the `_restoreRefractoryBeforeBeat` line in deleteMessage.
//  * clock off: the send-handoff per-reply tick.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show NsfwService;
import '../../helpers/chat_db_teardown.dart';
import '../../helpers/refractory_judges.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_refr_').path;
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
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the refractory clock test.',
        firstMessage: 'The porch light hums.',
        imagePath: 'refr-mara.png',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-refr-mara',
    );
    await chat.setRealismEnabled(true);
    await chat.setNsfwCooldownEnabled(true);
  });

  tearDown(() async {
    debugPrint = previousPrint ?? debugPrint;
    await disposeChatThenCloseDb(chat, db);
  });

  NsfwService nsfw() => chat.nsfwService;

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

  Future<void> send(String text, {int minutes = 5, bool climax = false}) async {
    llm
      ..minutes = minutes
      ..climax = climax;
    await chat.sendMessage(text);
    await settle();
  }

  group('clock on', () {
    test('75 min set at climax from refractory_turns 5; a 20-minute beat '
        'leaves 55', () async {
      llm.refractoryTurns = 5;
      await send('The wave crests and breaks over us both.', climax: true);
      expect(nsfw().refractoryMinutesRemaining, 75);
      expect(nsfw().refractoryMinutesTotal, 75);
      expect(nsfw().refractoryWords.chip, 'Refractory: about 75 min');

      await send('We lie still for a while.', minutes: 20);
      expect(
        nsfw().refractoryMinutesRemaining,
        55,
        reason: 'the beat the clock just applied is the refractory\'s tick',
      );
      expect(nsfw().refractoryWords.chip, 'Refractory: about 55 min');
      expect(
        llm.judgePrompts.any((p) => p.contains('(about 75 min left)')),
        isTrue,
        reason: 'the eval note reads the minutes, before this beat ticked',
      );
    });

    test('a two-hour skip ends a 75-minute refractory', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      expect(nsfw().refractoryMinutesRemaining, 75);
      final before = chat.timeService.clock;

      await send('(OOC: two hours later) We wander back out to the porch.');
      expect(
        chat.timeService.clock.difference(before).inMinutes,
        greaterThanOrEqualTo(120),
        reason: 'baseline: the skip moved the clock at send',
      );
      expect(
        nsfw().refractoryMinutesRemaining,
        0,
        reason:
            'the skip happened before this reply stamped its own before; '
            'the beat is measured from the last reply\'s after',
      );
      expect(nsfw().refractoryMinutesTotal, 0);
    });

    test('"next morning" ends it', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      expect(nsfw().refractoryMinutesRemaining, 75);

      await send('(OOC: skip to the next morning) Coffee on the porch.');
      expect(nsfw().refractoryMinutesRemaining, 0);
    });

    test('the opening turn is exactly the first reply after the climax '
        'reply, even when that reply took no time', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      expect(nsfw().isOpeningAfterglowTurn, isTrue);
      expect(
        llm.lastReplyWasOpening,
        isFalse,
        reason: 'the climax reply itself was written before the climax',
      );

      await send('Stay right here.', minutes: 0);
      expect(
        llm.lastReplyWasOpening,
        isTrue,
        reason: 'the first reply after the climax reply is the opening turn',
      );
      expect(nsfw().refractoryMinutesRemaining, 75, reason: 'same moment');
      expect(nsfw().isOpeningAfterglowTurn, isFalse);

      await send('Still here?', minutes: 0);
      expect(
        llm.lastReplyWasOpening,
        isFalse,
        reason: 'a same-moment second reply is no longer the opening turn',
      );
      expect(nsfw().refractoryMinutesRemaining, 75);
    });

    test('Continue is the same beat: no tick, and the opening turn stays '
        'unspoken', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      // No second climax in the continuation: a fresh one would reset the
      // refractory and hide any tick.
      llm
        ..minutes = 30
        ..climax = false;
      await chat.continueGeneration();
      await settle();
      expect(
        nsfw().refractoryMinutesRemaining,
        75,
        reason: 'the clock does not move on Continue, so nothing ticks',
      );
      expect(nsfw().isOpeningAfterglowTurn, isTrue);

      await send('Stay right here.', minutes: 20);
      expect(llm.lastReplyWasOpening, isTrue);
      expect(nsfw().refractoryMinutesRemaining, 55);
    });

    test('regen restores the minutes and the flag, and replays the beat '
        'once', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      await send('We lie still for a while.', minutes: 20);
      expect(nsfw().refractoryMinutesRemaining, 55);
      expect(nsfw().refractoryOpened, isTrue);

      llm.minutes = 30;
      await chat.regenerateLastMessage();
      await settle();
      expect(
        llm.lastReplyWasOpening,
        isTrue,
        reason: 'the replay starts from the restored flag: still the opening',
      );
      expect(
        nsfw().refractoryMinutesRemaining,
        45,
        reason: '75 restored, then the replayed 30-minute beat, once',
      );
      expect(nsfw().refractoryOpened, isTrue);

      llm.minutes = 20;
      await chat.regenerateLastMessage();
      await settle();
      expect(
        nsfw().refractoryMinutesRemaining,
        55,
        reason: 'the same inputs reproduce the same refractory',
      );
    });

    test('a tail delete restores the minutes and the flag', () async {
      await send('The wave crests and breaks over us both.', climax: true);
      await send('We lie still for a while.', minutes: 20);
      expect(nsfw().refractoryMinutesRemaining, 55);
      expect(nsfw().refractoryOpened, isTrue);

      chat.deleteMessage(chat.messages.length - 1);
      await settle();
      expect(nsfw().refractoryMinutesRemaining, 75);
      expect(nsfw().refractoryOpened, isFalse);
      expect(nsfw().isOpeningAfterglowTurn, isTrue);
    });
  });

  group('clock off', () {
    setUp(() => chat.setPassageOfTimeEnabled(false));

    test('three replies end a 45; the chip counts replies', () async {
      llm.refractoryTurns = 3;
      await send('The wave crests and breaks over us both.', climax: true);
      expect(nsfw().refractoryMinutesRemaining, 45);
      expect(nsfw().refractoryWords.chip, 'Refractory: 3 replies');

      await send('Stay right here.');
      expect(nsfw().refractoryMinutesRemaining, 30);
      expect(nsfw().refractoryWords.chip, 'Refractory: 2 replies');
      expect(
        llm.judgePrompts.any((p) => p.contains('(2 replies left)')),
        isTrue,
        reason: 'the eval note counts replies with the clock off',
      );

      await send('Still here?');
      expect(nsfw().refractoryWords.chip, 'Refractory: 1 reply');

      await send('Ready to go inside?');
      expect(nsfw().refractoryMinutesRemaining, 0);
      expect(nsfw().refractoryWords.chip, isEmpty);
    });

    test(
      'regen gives back the reply\'s quarter hour and takes it once',
      () async {
        llm.refractoryTurns = 3;
        await send('The wave crests and breaks over us both.', climax: true);
        await send('Stay right here.');
        expect(nsfw().refractoryMinutesRemaining, 30);

        await chat.regenerateLastMessage();
        await settle();
        expect(
          nsfw().refractoryMinutesRemaining,
          30,
          reason: '45 restored from the receipt, then the regen\'s own reply',
        );
        expect(llm.lastReplyWasOpening, isTrue);
      },
    );
  });
}
