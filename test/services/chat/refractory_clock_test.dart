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
import 'package:front_porch_ai/services/chat/chat.dart'
    show NsfwService, Refractory;
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
    await storage.realismSettings.setNsfwCooldownDefault(true);
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

  // Three layers: Porch Life (with 18+) allows Afterglow, and each chat's own
  // switch decides. The 2026-10-24 report (a chat stored "off" that nothing
  // could flip) is answered by that switch being back on the sidebar and the
  // phone, and by new chats taking theirs from the card.
  test("Porch Life allows Afterglow and the chat's own switch decides; "
      'Porch Life off or 18+ off turns it off', () async {
    await chat.setAfterglowEnabled(false);
    expect(
      nsfw().nsfwCooldownEnabled,
      isFalse,
      reason: 'the chat is switched off',
    );
    await chat.setAfterglowEnabled(true);
    expect(nsfw().nsfwCooldownEnabled, isTrue);
    llm.refractoryTurns = 5;
    await send('The wave crests and breaks over us both.', climax: true);
    expect(nsfw().refractoryMinutesRemaining, 75, reason: 'the climax landed');

    await storage.realismSettings.setNsfwCooldownDefault(false);
    expect(nsfw().nsfwCooldownEnabled, isFalse);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await storage.realismSettings.setAdultThemesEnabled(false);
    expect(nsfw().nsfwCooldownEnabled, isFalse, reason: 'Afterglow needs 18+');
  });

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

  // Recovery overhaul PR 3: the soft gate, through real 1:1 turns with the
  // clock off — each reply of the speaker's is exactly 15 minutes, so the
  // window and the peak aging have exact numbers (quantization floor: the
  // 15-minute window lasts one reply; Needs precedent, decision 1).
  group('soft gate (PR 3)', () {
    setUp(() async {
      chat.setPassageOfTimeEnabled(false);
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
            recovery: const RecoveryProfile(recoveryMode: kRecoveryModeSoft),
          ),
        )..dbId = 'char-refr-mara',
      );
      await chat.setRealismEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
    });

    test(
      'a soft card takes the 15-min window, not the judge\'s lock',
      () async {
        llm.refractoryTurns = 5; // a hard body would lock 75 — ignored here
        nsfw().setArousalLevel(100);
        await send('The wave crests over us both.', climax: true);
        expect(
          nsfw().refractoryMinutesRemaining,
          15,
          reason:
              'the tenderness window is fixed (decision 4) — 75 here '
              'means the soft card still took the judge\'s hard length',
        );
        expect(nsfw().refractory.soft, isTrue);
        expect(
          nsfw().arousalLevel,
          90,
          reason: 'peak 1 costs round(0.2 × (100−50) × 1) — never zero',
        );
        expect(nsfw().refractoryPeaksLastHour, 1);
        expect(nsfw().refractoryWords.chip, 'Tender for 1 reply · peak 1');
        expect(
          chat.messages.last.activeMetadata?['pre_climax_refractory'],
          isA<Map>(),
          reason: 'PR 3 stamps the whole pre-climax body beside the arousal',
        );
      },
    );

    test(
      'the ladder speaks glow and tender across the clock-on hour',
      () async {
        chat.setPassageOfTimeEnabled(true); // the fake advances 5 min a beat
        nsfw().setArousalLevel(100);
        await send('The wave crests over us both.', climax: true);

        await send('Stay right here.'); // prompt assembled before this beat
        expect(
          llm.replyPrompts.last,
          contains('oversensitive in the best way'),
          reason: 'the first reply after a soft climax reads the glow rung',
        );

        await send('Nothing to add, just company.'); // window 10, opened
        expect(
          llm.replyPrompts.last,
          contains('still humming from it'),
          reason: 'while the window runs, the tender rung carries closeness',
        );
        expect(llm.replyPrompts.last, isNot(contains('cannot respond yet')));

        await send('The fireflies are out.', minutes: 15); // window spent
        await send('Getting late.', minutes: 15); // peak 30
        expect(
          llm.replyPrompts.last,
          contains('is warm again'),
          reason:
              'the window is gone but the hour is not — the cuddle beat '
              'holds',
        );

        await send('Half past eight.', minutes: 15); // 40 → 55
        await send('Time flies.', minutes: 15); // 55 — still counted
        await send('Almost dark.', minutes: 15); // 70 past the hour: it drops
        expect(nsfw().refractoryPeaksLastHour, 0);
        expect(
          llm.replyPrompts.last,
          isNot(contains('warm again')),
          reason: 'a story hour after the peak, the normal ladder returns',
        );
        expect(
          llm.replyPrompts.last,
          contains('peak of arousal'),
          reason: 'arousal never dropped — 90 reads the top arousal rung now',
        );
      },
    );

    test(
      'clock off: the window is one reply, so warm-again takes it at once',
      () async {
        // The quantization floor, Needs precedent (decision 1): with the
        // clock off, the speaker's next reply burns the whole 15-minute
        // window in its own handoff tick — that prompt already reads the
        // warm-again rung, and the half-weight damping covered the climax
        // turn itself.
        nsfw().setArousalLevel(100);
        await send('The wave crests over us both.', climax: true);
        expect(nsfw().refractoryMinutesRemaining, 15);

        await send('Stay right here.');
        expect(
          llm.replyPrompts.last,
          contains('is warm again'),
          reason:
              'the handoff tick spent the window before this prompt was '
              'assembled — the ordering the hard-lock chip already counts on',
        );
        expect(nsfw().refractoryPeaksLastHour, 1, reason: 'peak 15 min old');
      },
    );

    test('a soft window expiring does not thaw a negative arousal', () async {
      nsfw().setArousalLevel(-20); // below the floor: the peak costs nothing
      await send('It passes quietly.', climax: true);
      expect(nsfw().arousalLevel, -20);
      await send('A beat of quiet.');
      expect(
        nsfw().arousalLevel,
        -20,
        reason:
            'the end-of-lock halving is hard-lock semantics; a soft '
            'window simply expires',
      );
    });

    test(
      'regen of peak 2 restores peak 1 and its body, not an empty one',
      () async {
        nsfw().setArousalLevel(100);
        await send('The wave crests over us both.', climax: true); // peak 1
        llm.refractoryTurns = 1;
        nsfw().setArousalLevel(95);
        await send('Again — let it crest once more.', climax: true); // peak 2
        expect(nsfw().refractoryPeaksLastHour, 2);
        expect(nsfw().arousalLevel, 77);

        llm.climax = false; // the regen itself does not climax
        await chat.regenerateLastMessage();
        await settle();
        expect(
          nsfw().arousalLevel,
          90,
          reason:
              'the pre-climax stamp restores 95, then the realism-snapshot '
              "replay — which owns the speaker's arousal (0453f71d) — lands "
              'the body as peak 1 recorded it',
        );
        expect(
          nsfw().refractoryPeaksLastHour,
          1,
          reason: 'peak 1 survives the rewind — a wipe to none would read 0',
        );
        expect(nsfw().refractoryMinutesRemaining, 0);
      },
    );

    test('a pre-PR-3 stamp (no body key) still clears to none', () async {
      // The installed base: replies written before PR 3 stamped only the
      // arousal. Regenerating one must behave exactly as it did yesterday.
      nsfw().setArousalLevel(100);
      await send('The wave crests over us both.', climax: true);
      final msg = chat.messages.last;
      final oldMeta = Map<String, dynamic>.from(msg.activeMetadata ?? {})
        ..remove('pre_climax_refractory');
      msg.activeMetadata = oldMeta;

      llm.climax = false;
      await chat.regenerateLastMessage();
      await settle();
      expect(nsfw().refractoryPeaksLastHour, 0);
      expect(nsfw().refractoryMinutesRemaining, 0);
      expect(
        nsfw().arousalLevel,
        100,
        reason: 'the arousal restore is old news',
      );
    });
  });

  group('warmth tail (PR 4)', () {
    Future<void> useCard({required String mode}) async {
      chat.setPassageOfTimeEnabled(true);
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Tess',
          description: 'Exists only inside the refractory clock test.',
          firstMessage: 'The porch light hums.',
          imagePath: 'refr-tess.png',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: true,
            needsSimEnabled: false,
            chaosModeEnabled: false,
            recovery: RecoveryProfile(recoveryMode: mode),
          ),
        )..dbId = 'char-refr-tess',
      );
      await chat.setRealismEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
    }

    test(
      'a hard tail freezes under the lock and ages from its first clear beat',
      () async {
        await useCard(mode: kRecoveryModeHard);
        llm.refractoryTurns = 4; // lock 60, tail 30
        nsfw().setArousalLevel(80);
        await send('The wave crests over us both.', climax: true);
        expect(nsfw().refractoryMinutesRemaining, 60);
        expect(nsfw().refractoryTailMinutes, 30);
        expect(nsfw().warmthTailActive, isFalse, reason: 'frozen under lock');

        await send('Stars, quiet ones.', minutes: 40);
        expect(nsfw().refractoryMinutesRemaining, 20);
        expect(
          nsfw().refractoryTailMinutes,
          30,
          reason: 'the tail does not age while the lock runs',
        );

        await send('Closer.', minutes: 20);
        expect(
          nsfw().refractoryTailMinutes,
          30,
          reason: 'the lock ends THIS beat — the tail starts frozen at seed',
        );
        expect(nsfw().warmthTailActive, isTrue);

        await send('Quieter still.', minutes: 10);
        expect(nsfw().refractoryTailMinutes, 20);

        await send('The hour turns.', minutes: 20);
        expect(nsfw().refractoryTailMinutes, 0);
        expect(nsfw().refractory, Refractory.none);
      },
    );

    test(
      'a soft tail waits for the last peak, then ages on the same ledger',
      () async {
        await useCard(mode: kRecoveryModeSoft);
        llm.refractoryTurns = 6; // would-be 90 → tail 45
        nsfw().setArousalLevel(100);
        await send('The wave crests over us both.', climax: true);
        expect(nsfw().refractoryMinutesRemaining, 15);
        expect(nsfw().refractoryTailMinutes, 45);

        await send('Humming still.', minutes: 20); // window over, peak 20
        expect(nsfw().refractoryPeaksLastHour, 1);
        expect(nsfw().refractoryTailMinutes, 45, reason: 'warm-again: frozen');

        await send('Slow breath.', minutes: 45); // peak 65 prunes
        expect(nsfw().refractoryPeaksLastHour, 0);
        expect(
          nsfw().refractoryTailMinutes,
          45,
          reason: 'the peak ages out THIS beat — aging starts next beat',
        );

        await send('Deeper in the evening.', minutes: 30);
        expect(nsfw().refractoryTailMinutes, 15);
        expect(nsfw().warmthTailActive, isTrue);

        await send('The lamp flickers.', minutes: 20);
        expect(nsfw().refractoryTailMinutes, 0);
      },
    );

    test('clock off: two replies of 15 age a 30-minute tail to none', () async {
      await useCard(mode: kRecoveryModeHard);
      chat.setPassageOfTimeEnabled(false);
      llm.refractoryTurns = 4; // lock 60 (4 replies), tail 30 (2 replies)
      nsfw().setArousalLevel(80);
      await send('The wave crests over us both.', climax: true);
      expect(nsfw().refractoryMinutesRemaining, 60);
      await send('One.'); // tick at send: 45
      await send('Two.'); // 30
      await send('Three.'); // 15
      await send('Four.'); // 0 — the lock ends THIS beat, tail starts frozen
      expect(nsfw().refractoryMinutesRemaining, 0);
      expect(nsfw().refractoryTailMinutes, 30, reason: 'frozen at seed');
      await send('Five.'); // tail 15
      expect(nsfw().refractoryTailMinutes, 15);
      await send('Six.'); // tail 0
      expect(nsfw().refractoryTailMinutes, 0);
      expect(nsfw().refractory, Refractory.none);
    });

    test('regen of a tailed beat rewinds the tail minutes exactly', () async {
      await useCard(mode: kRecoveryModeHard);
      llm.refractoryTurns = 4; // lock 60, tail 30
      nsfw().setArousalLevel(80);
      await send('The wave crests over us both.', climax: true);
      await send('Stars, quiet ones.', minutes: 70); // lock ends → tail 30
      await send('Quieter still.', minutes: 10); // tail 20
      expect(nsfw().refractoryTailMinutes, 20);

      llm
        ..climax =
            false // the regen itself does not climax
        ..minutes = 0; // and the regen beat spans no story time
      await chat.regenerateLastMessage();
      await settle();
      expect(
        nsfw().refractoryTailMinutes,
        30,
        reason:
            'the pre-beat receipt put the body back as it found it — '
            'a receipt that dropped the nested tail would read 20 or 0',
      );
    });
  });
}
