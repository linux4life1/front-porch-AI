// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chance Time wheel: the 18+ gate on adult events, the category spread, pair
// and user events, repeat skipping, and the frequency / cooldown math.

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../../integration_test/support/fake_backend.dart';
import '../../../helpers/chat_db_teardown.dart';

ChaosModeService _chaos({
  bool adult = false,
  bool spicy = false,
  ChaosFrequency frequency = ChaosFrequency.normal,
}) {
  return ChaosModeService(
    onNotify: () {},
    onSaveChat: () async {},
    onSetPendingRealismMetadata: (_, _) {},
    isAdultAllowed: () => adult,
    getFrequency: () => frequency,
  )..seedFromGroupOrExt(true, spicy);
}

bool _isAdult(String text) => chaosEventFor(text)!.adult;

/// Desire-asserting adult events a HARD refractory lock must hold back.
const _locked = {
  '{{char}} is visibly aroused at the most inconvenient moment imaginable '
      'and is scrambling',
  '{{char}} is trying extremely hard to hide a visible physical reaction to '
      'someone attractive nearby',
  '{{char}} is suddenly, intensely in the mood and it is very hard to hide',
  'A long dry spell has caught up with {{char}} and they are restless, '
      'flustered, and thinking about little else',
};

void main() {
  group('18+ gate', () {
    test(
      'spicy on but 18+ themes off: no adult event ever reaches a wheel',
      () {
        final chaos = _chaos(adult: false, spicy: true);
        expect(chaos.spicyActive, isFalse);
        for (var i = 0; i < 200; i++) {
          expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
        }
      },
    );

    test('a service built without the 18+ callback never allows adult', () {
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
      )..seedFromGroupOrExt(true, true);
      expect(chaos.adultAllowed, isFalse);
      expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
    });

    test('18+ themes on but spicy off: no adult events', () {
      final chaos = _chaos(adult: true, spicy: false);
      for (var i = 0; i < 100; i++) {
        expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
      }
    });

    test('both on: the wheel carries exactly the adult slots', () {
      final chaos = _chaos(adult: true, spicy: true);
      for (var i = 0; i < 50; i++) {
        final wheel = chaos.spinWheelEvents();
        expect(wheel.length, 8);
        expect(wheel.toSet().length, 8);
        expect(wheel.where(_isAdult).length, kAdultWheelSlots);
      }
    });

    test('turning 18+ themes off takes effect on the next wheel', () {
      var adult = true;
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        isAdultAllowed: () => adult,
      )..seedFromGroupOrExt(true, true);
      expect(chaos.spinWheelEvents().where(_isAdult), isNotEmpty);
      adult = false;
      expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
    });
  });

  group('wheel contents', () {
    test('SFW slots come from eight different categories', () {
      for (var seed = 0; seed < 50; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: false,
          allowPair: true,
          allowUser: true,
          random: Random(seed),
        );
        final cats = wheel.map((t) => chaosEventFor(t)!.category).toSet();
        expect(cats.length, 8, reason: 'seed $seed: $wheel');
      }
    });

    test('pair events need a partner; user events need the user', () {
      for (var seed = 0; seed < 200; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: false,
          allowUser: false,
          random: Random(seed),
        );
        expect(wheel.where((t) => t.contains('{{other}}')), isEmpty);
        expect(wheel.where((t) => t.contains('{{user}}')), isEmpty);
      }
    });

    test('recently used events are skipped', () {
      final chaos = _chaos(adult: true, spicy: true);
      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        final wheel = chaos.spinWheelEvents();
        expect(wheel.where(seen.contains), isEmpty);
        for (final e in wheel) {
          chaos.rememberEvent(e);
          seen.add(e);
        }
      }
    });

    test('every event is unique and uses only known placeholders', () {
      final texts = kAllChaosEvents.map((e) => e.text).toList();
      expect(texts.toSet().length, texts.length);
      for (final t in texts) {
        final names = RegExp(r'\{\{(\w+)\}\}').allMatches(t).map((m) => m[1]);
        expect(
          names.every(const {'char', 'user', 'other'}.contains),
          isTrue,
          reason: t,
        );
      }
    });
  });

  group('frequency and cooldown', () {
    test('Wild grows 10 a turn, Rare 2', () {
      final wild = _chaos(frequency: ChaosFrequency.wild);
      wild.checkAndTickChaosPressure();
      expect(wild.chaosPressure, 10);
      final rare = _chaos(frequency: ChaosFrequency.rare);
      rare.checkAndTickChaosPressure();
      expect(rare.chaosPressure, 2);
    });

    test('after an event lands, the cooldown turns pass with no growth '
        'and no roll', () async {
      final chaos = _chaos(frequency: ChaosFrequency.rare);
      await chaos.applyPreparedEvent('A bird lands.');
      expect(chaos.cooldownTurns, ChaosFrequency.rare.cooldown);
      for (var i = 0; i < ChaosFrequency.rare.cooldown; i++) {
        expect(chaos.checkAndTickChaosPressure(), isFalse);
        expect(chaos.chaosPressure, 0);
      }
      expect(chaos.cooldownTurns, 0);
      chaos.checkAndTickChaosPressure();
      expect(chaos.chaosPressure, ChaosFrequency.rare.growth);
    });

    test('an unknown stored frequency reads as Normal', () {
      expect(ChaosFrequency.fromName('bogus'), ChaosFrequency.normal);
      expect(ChaosFrequency.fromName(null), ChaosFrequency.normal);
      expect(ChaosFrequency.fromName('wild'), ChaosFrequency.wild);
    });
  });

  // Recovery overhaul PR 6: the wheel respects the hard lock. Exactly the
  // events that ASSERT the speaker's own desire leave the pool while that
  // body is locked — every other event (and the whole SFW wheel) spins as
  // before, and a soft-gate body never loses one.
  group('the hard lock respects the wheel (PR 6)', () {
    const locked = {
      '{{char}} is visibly aroused at the most inconvenient moment '
          'imaginable and is scrambling',
      '{{char}} is trying extremely hard to hide a visible physical '
          'reaction to someone attractive nearby',
      '{{char}} is suddenly, intensely in the mood and it is very hard '
          'to hide',
      'A long dry spell has caught up with {{char}} and they are '
          'restless, flustered, and thinking about little else',
    };

    test('exactly the four desire-asserting events carry the tag', () {
      final tagged = kAllChaosEvents
          .where((e) => e.desireAsserting)
          .map((e) => e.text)
          .toSet();
      expect(tagged, locked);
      expect(
        kAllChaosEvents.where((e) => e.desireAsserting).every((e) => e.adult),
        isTrue,
        reason: 'a desire event that is not adult would gate into SFW wheels',
      );
    });

    test('the locked wheel never speaks a tagged event, and stays full', () {
      for (var seed = 0; seed < 200; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: true,
          allowUser: true,
          hardLockActive: true,
          random: Random(seed),
        );
        expect(wheel.length, 8);
        expect(wheel.toSet().length, 8);
        expect(
          wheel.where(locked.contains),
          isEmpty,
          reason: 'seed $seed narrates arousal under a hard lock: $wheel',
        );
        expect(
          wheel.where(_isAdult).length,
          kAdultWheelSlots,
          reason: 'the remaining adult pool backfills — no dead slots',
        );
      }
    });

    test('the unlocked wheel still serves them', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        seen.addAll(
          buildChaosWheel(
            includeAdult: true,
            allowPair: true,
            allowUser: true,
            random: Random(seed),
          ).where(locked.contains),
        );
      }
      expect(
        seen,
        locked,
        reason: 'a baseline wheel must still be able to land each one',
      );
    });

    test('the recent-skip fallback cannot sneak one back under lock', () {
      // Saturate recency with every OTHER adult text: the "not enough
      // fresh" fallback hands back the whole pool, and the tagged four
      // were already pulled BEFORE that branch — never after.
      final others = [
        for (final e in kAllChaosEvents)
          if (e.adult && !locked.contains(e.text)) e.text,
      ];
      for (var seed = 0; seed < 50; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: true,
          allowUser: true,
          hardLockActive: true,
          recent: others,
          random: Random(seed),
        );
        expect(wheel.where(locked.contains), isEmpty, reason: 'seed $seed');
        expect(wheel.length, 8);
      }
    });

    test('the service gate is live per spin, and absent means never gated', () {
      var lockedNow = true;
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        isAdultAllowed: () => true,
        isHardLockActive: () => lockedNow,
      )..seedFromGroupOrExt(true, true);
      for (var i = 0; i < 100; i++) {
        expect(chaos.spinWheelEvents().where(locked.contains), isEmpty);
      }
      lockedNow = false; // the window passes mid-session
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        seen.addAll(chaos.spinWheelEvents().where(locked.contains));
      }
      expect(seen, isNotEmpty);
      // A service built without the closure (every other host) never gates.
      final ungated = _chaos(adult: true, spicy: true);
      final seen2 = <String>{};
      for (var i = 0; i < 300; i++) {
        seen2.addAll(ungated.spinWheelEvents().where(locked.contains));
      }
      expect(seen2, isNotEmpty);
    });
  });

  // Recovery overhaul PR 6, end to end through the real wiring: the wheel
  // ChatService builds for a Chance Time spin pulls the desire-asserting
  // adult events while the attributed body is mid a HARD refractory lock,
  // and serves them again the moment the lock (or a soft body) says desire
  // is honest. The pool-level contract lives in chaos_wheel_test.dart; this
  // file pins the CHAIN — 18+ themes, the chat's spicy switch, the closure,
  // and the live refractory — because a silently missing closure param is
  // exactly the hole that made climax detection optional once.
  group('hard refractory lock through the ChatService wiring', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.createTempSync('fpai_chaoslock_').path;
          }
          return null;
        });

    late FakeBackendServer backend;
    late AppDatabase db;
    late ChatService chat;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
        // Seeds the app-wide 18+ themes switch (adultThemesEnabled reads it
        // live when no explicit choice was stored).
        'nsfw_cooldown_default': true,
      });
      backend = await FakeBackendServer.start(replyPieces: ['She nods.']);
      db = AppDatabase.forTesting();
      final storage = StorageService();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      await storage.initialized;
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Mara',
          description: 'Exists only inside the chaos hard-lock test.',
          firstMessage: 'The porch light hums.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: true,
          ),
        )..dbId = 'char-chaos-lock',
      );
      await chat.setChaosNsfwEnabled(true);
    });

    tearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });

    Set<String> seenLockedOver(int spins) {
      final seen = <String>{};
      for (var i = 0; i < spins; i++) {
        seen.addAll(chat.spinWheelEvents().where(_locked.contains));
      }
      return seen;
    }

    test('unlocked and spicy: the wheel serves the desire events', () {
      expect(chat.nsfwService.refractory.running, isFalse);
      expect(
        seenLockedOver(200),
        isNotEmpty,
        reason:
            'baseline must be able to land them, or the gate proves '
            'nothing',
      );
    });

    test('a hard lock pulls them from every wheel, wheel stays full', () {
      chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
      for (var i = 0; i < 100; i++) {
        final wheel = chat.spinWheelEvents();
        expect(wheel.length, 8);
        expect(wheel.where(_locked.contains), isEmpty, reason: '$wheel');
      }
    });

    test('a soft body keeps them — the gate is hard lock only', () {
      // Multiorgasmic characters hold their arousal through the window, so
      // "visibly aroused" is the TRUTH for them mid-window, not a lie.
      chat.nsfwService.setRefractory(Refractory.tenderness([0]));
      expect(chat.nsfwService.refractory.running, isTrue);
      expect(chat.nsfwService.refractory.soft, isTrue);
      expect(seenLockedOver(300), isNotEmpty);
    });

    // Afterglow off hides the recovery and keeps it; a hidden lock must not
    // steer the wheel, as no lock did while off used to zero it.
    test("a chat switched off keeps its lock hidden, and the wheel serves "
        'them', () async {
      chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
      expect(chat.afterglowChatSwitch, isTrue);
      expect(seenLockedOver(100), isEmpty, reason: 'baseline: the lock holds');
      await chat.setAfterglowEnabled(false);
      expect(chat.nsfwService.refractory.running, isTrue, reason: 'kept');
      expect(seenLockedOver(300), isNotEmpty);
    });

    test('the gate is live: releasing the lock serves them again', () {
      chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(4));
      expect(seenLockedOver(100), isEmpty);
      chat.nsfwService.setRefractory(Refractory.none);
      expect(seenLockedOver(300), isNotEmpty);
    });

    // Review M1: a manual SPIN NOW parks WITHOUT halting generation. The
    // beat between spin and accept can carry a climax (1:1) or rotate a
    // group pointer onto a body locked the whole window. Accept must re-gate
    // against the body the event actually attributes to.
    test('a parked tagged event cannot land on a now-locked body', () async {
      final tagged = kAllChaosEvents.firstWhere((e) => e.desireAsserting).text;
      // Spin happened unlocked; the climax lands before Accept.
      chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
      await chat.applyChanceTimeResult(tagged, 'Mara');
      final injection = chat.chaosModeService.pendingChaosInjection;
      expect(injection, isNotNull, reason: 'the spin still pays out');
      expect(
        injection,
        isNot(chat.resolveChanceTimeEvent(tagged, 'Mara')),
        reason: 'the parked "visibly aroused" must not print under Lust: 0',
      );
      // What lands is a legal event: untagged or from the gated wheel.
      final applied = kAllChaosEvents.where(
        (e) => chat.resolveChanceTimeEvent(e.text, 'Mara') == injection,
      );
      expect(
        applied.every((e) => !e.desireAsserting),
        isTrue,
        reason: 'a desire-asserting event survived the re-gate: $injection',
      );
    });

    test('unlocked, the parked tagged event lands verbatim', () async {
      final tagged = kAllChaosEvents.firstWhere((e) => e.desireAsserting).text;
      await chat.applyChanceTimeResult(tagged, 'Mara');
      expect(
        chat.chaosModeService.pendingChaosInjection,
        chat.resolveChanceTimeEvent(tagged, 'Mara'),
      );
    });

    test('a locked body still receives untagged events untouched', () async {
      final plain = kAllChaosEvents
          .firstWhere((e) => !e.desireAsserting && e.text.contains('{{char}}'))
          .text;
      chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
      await chat.applyChanceTimeResult(plain, 'Mara');
      expect(
        chat.chaosModeService.pendingChaosInjection,
        chat.resolveChanceTimeEvent(plain, 'Mara'),
      );
    });
  });

  // A group has no active character between turns. Chance Time named the
  // first member to answer on every turn after (the post-reply pass left them
  // active), and in random turn order it could not name who answers at all:
  // the speaker was picked only once the turn began.
  group('Chance Time in a group names the member who answers', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return Directory.systemTemp.createTempSync('fpai_chaosgrp_').path;
          }
          return null;
        });

    late FakeBackendServer backend;
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': false,
      });
      backend = await FakeBackendServer.start(replyPieces: ['She nods.']);
      db = AppDatabase.forTesting();
      storage = StorageService();
      chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      await storage.initialized;
      await db.insertGroup(GroupsCompanion.insert(id: 'grp-ct', name: 'Trio'));
      for (final name in ['Ada', 'Bea', 'Cy']) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: 'mem-${name.toLowerCase()}',
            groupId: 'grp-ct',
            name: name,
            avatarFilename: Value('${name.toLowerCase()}.png'),
          ),
        );
      }
    });

    tearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });

    Future<void> enter(TurnOrder order) => chat.setActiveGroup(
      GroupChat(id: 'grp-ct', name: 'Trio', turnOrder: order),
      groupRepo: GroupChatRepository(storage, db),
    );

    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('round robin: once Ada has answered, the event and the prompt name '
        'Bea', () async {
      await enter(TurnOrder.roundRobin);
      await chat.sendMessage('Evening, all.');
      await settle();
      expect(chat.messages.last.sender, 'Ada');
      expect(
        chat.activeCharacter,
        isNull,
        reason: 'no member stays active once they have answered',
      );

      expect(chat.chanceTimeSpeakerName, 'Bea');
      await chat.applyChanceTimeResult('A lantern gutters out.', 'Bea');
      await chat.triggerNextCharacter();
      await settle();
      expect(chat.messages.last.sender, 'Bea');
      expect(backend.lastChatBody, contains("Write Bea's immediate reaction"));
      expect(backend.lastChatBody, isNot(contains("Write Ada's")));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('random order: the spin picks the member who answers', () async {
      await enter(TurnOrder.random);
      expect(chat.nextCharacter, isNull, reason: 'random picks at the turn');

      chat.spinWheelEvents();
      final named = chat.chanceTimeSpeakerName;
      expect(['Ada', 'Bea', 'Cy'], contains(named));
      expect(chat.nextCharacter?.name, named, reason: 'held as next speaker');

      await chat.applyChanceTimeResult('A lantern gutters out.', named);
      await chat.sendMessage('Evening, all.');
      await settle();
      expect(chat.messages.last.sender, named);
      expect(
        backend.lastChatBody,
        contains("Write $named's immediate reaction"),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test("random order: a turn between the phone's spin and Accept, and "
        'Accept applies what the reveal showed', () async {
      await enter(TurnOrder.random);
      await chat.setChaosModeEnabled(true);
      expect(chat.requestManualChanceTime(), isTrue);
      final shown = chat.webChanceTimeDisplay;
      final named = chat.nextCharacter?.name;
      expect(['Ada', 'Bea', 'Cy'], contains(named));
      await chat.triggerNextCharacter();
      await settle();
      expect(chat.messages.last.sender, named);
      expect(chat.nextCharacter, isNull, reason: 'that turn took the pick');
      expect(chat.webChanceTimeDisplay, shown, reason: 'the reveal holds');

      await chat.acceptPendingChanceTime();
      expect(chat.chaosModeService.pendingChaosInjection, shown);
      expect(chat.nextCharacter?.name, named, reason: 'held as the next pick');
      await chat.sendMessage('What was that?');
      await settle();
      expect(chat.messages.last.sender, named);
      expect(
        backend.lastChatBody,
        contains("Write $named's immediate reaction"),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
