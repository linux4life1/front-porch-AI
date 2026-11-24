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

// The bogey rate promise (docs/design/boons-and-bogies.md §6): "the median
// gap is 7–9 replies". This runs 10k replies on the real [BogeyRoll] math and
// asserts the promise. Move the constants, not this test — the spec says the
// numbers are tuning and the gap is the contract.

import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/bogey_roll.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/support/fake_backend.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_bogey_').path;
        }
        return null;
      });
}

/// The marker [GrowthService.bogeyNudgeFor] puts in a reply prompt.
const _nudge = '[SCENE NOTE';

void main() {
  test('median gap between bogey fires is 7-9 replies over 10k', () {
    final random = Random(20261123);
    var pressure = 0;
    var cooldown = 0;
    var sinceFire = 0;
    final gaps = <int>[];

    for (var reply = 0; reply < 10000; reply++) {
      sinceFire++;
      final tick = BogeyRoll.tick(
        pressure: pressure,
        cooldown: cooldown,
        random: random,
      );
      pressure = tick.pressure;
      cooldown = tick.cooldown;
      if (!tick.fired) continue;
      gaps.add(sinceFire);
      sinceFire = 0;
      pressure = 0;
      cooldown = BogeyRoll.cooldownAfterFire(random);
    }

    expect(gaps.length, greaterThan(500), reason: 'the roll must fire at all');
    gaps.sort();
    final median = gaps[gaps.length ~/ 2];
    expect(
      median,
      inInclusiveRange(7, 9),
      reason: 'median gap $median outside the promised 7–9 (spec §6)',
    );
  });

  test('chance is capped at 45% and pressure never exceeds its cap', () {
    // Drive the gauge to saturation: with pressure at the cap, the chance
    // must stay at the 45-point ceiling (a 60% fire rate would fail this).
    final random = Random(7);
    var pressure = BogeyRoll.pressureCap;
    var fires = 0;
    const trials = 20000;
    for (var i = 0; i < trials; i++) {
      final tick = BogeyRoll.tick(
        pressure: pressure,
        cooldown: 0,
        random: random,
      );
      pressure = tick.pressure;
      if (tick.fired) fires++;
    }
    final rate = fires / trials;
    expect(rate, lessThanOrEqualTo(0.47));
    expect(rate, greaterThanOrEqualTo(0.40));
  });

  test('BogeyRoll.reply — the function the turn persists — keeps the 7-9 '
      'median and never fires on two replies in a row', () {
    final random = Random(7);
    BogeyGauge gauge = (pressure: 0, cooldown: 0);
    final gaps = <int>[];
    var sinceFire = 0;
    var firedLast = false;
    for (var i = 0; i < 10000; i++) {
      final reply = BogeyRoll.reply([gauge], random);
      gauge = reply.after.single;
      sinceFire++;
      if (reply.fired == 0) {
        expect(firedLast, isFalse, reason: 'reply $i fired right after one');
        expect(gauge.cooldown, inInclusiveRange(1, 3));
        expect(gauge.pressure, 0);
        gaps.add(sinceFire);
        sinceFire = 0;
      }
      firedLast = reply.fired == 0;
    }
    gaps.sort();
    expect(gaps[gaps.length ~/ 2], inInclusiveRange(7, 9));
  });

  test('a fire counts toward the ladder, held one below Master', () {
    expect(BogeyRoll.advanceAfterFire(0), 1);
    expect(BogeyRoll.advanceAfterFire(10), 11);
    expect(BogeyRoll.advanceAfterFire(11), 11);
  });

  group('bogey rolls in a real turn (fake backend, Realism on)', () {
    late AppDatabase db;
    late StorageService storage;
    late ChatService chat;
    late FakeBackendServer backend;
    late CharacterCard card;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      _mockPathProvider();
    });

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
      });
      db = AppDatabase.forTesting();
      backend = await FakeBackendServer.start(
        replyPieces: ['She leans on the porch rail.'],
      );
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
      await storage.memorySettings.setCharacterEvolutionEnabled(true);
      await storage.memorySettings.setBoonsBogiesEnabled(true);
      await storage.realismSettings.setOneShotMode(OneShotMode.off);
      card = CharacterCard(
        name: 'Bogey Tester',
        description: 'Exists only inside the bogey turn test.',
        firstMessage: 'Welcome to the porch.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
          chaosModeEnabled: false,
          traitKit: [
            TraitKitEntry(
              kind: TraitKitEntry.kindBogey,
              text: 'Knocks things over when nervous',
            ),
          ],
        ),
      )..dbId = 'char-bogey-turn';
    });

    tearDown(() async {
      chat.dispose();
      await backend.close();
      await db.close();
    });

    Future<void> settle() async {
      for (
        var i = 0;
        i < 400 && (chat.isGenerating || chat.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<GrowthRingData> bogey() async {
      final rings = await db.getGrowthRings(
        chat.currentSessionId!,
        chat.characterIdFor(card),
      );
      return rings.singleWhere((r) => r.category == 'bogey');
    }

    /// One send, and the reply prompt it produced (the scene-guest name
    /// check is the only other CHAT-classified call).
    Future<String> send(String text) async {
      final mark = backend.chatBodies.length;
      await chat.sendMessage(text);
      await settle();
      final replies = backend.chatBodies
          .skip(mark)
          .where((b) => !b.contains('respond with ONLY'))
          .toList();
      expect(replies, hasLength(1), reason: 'one reply prompt per send');
      return replies.single;
    }

    test('a fire counts, cools down, and its nudge rides only its own '
        'reply', () async {
      await chat.setActiveCharacter(card);
      await settle();
      final start = (await bogey()).advanceCount;
      var fires = 0;
      var nudgedLast = false;
      for (var i = 0; i < 30; i++) {
        final nudged = (await send('Turn $i on the porch.')).contains(_nudge);
        if (nudged) {
          // Two in a row was the stale cache (the delivered nudge never
          // cleared) or a fire with no cooldown.
          expect(nudgedLast, isFalse, reason: 'reply $i repeated the nudge');
          fires++;
        }
        nudgedLast = nudged;
      }
      expect(fires, greaterThan(0), reason: '30 replies with no fire');
      expect(
        (await bogey()).advanceCount,
        start + fires,
        reason: 'every fire is one step of the bogey ladder (§3.2)',
      );
    }, timeout: const Timeout(Duration(minutes: 4)));

    test(
      'a strong scene holds the roll on THIS message, pressure and all',
      () async {
        backend.emotionIntensity = 'strong';
        await chat.setActiveCharacter(card);
        await settle();
        final before = await bogey();
        for (var i = 0; i < 10; i++) {
          final reply = await send('A hard thing, said plainly. ($i)');
          expect(reply, isNot(contains(_nudge)));
        }
        final after = await bogey();
        expect(after.bogeyPressure, before.bogeyPressure);
        expect(after.advanceCount, before.advanceCount);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('Porch Life "Bogey rolls" off: no roll at all', () async {
      await storage.memorySettings.setBogeyRollsEnabled(false);
      await chat.setActiveCharacter(card);
      await settle();
      final before = await bogey();
      for (var i = 0; i < 6; i++) {
        expect(await send('Turn $i, rolls off.'), isNot(contains(_nudge)));
      }
      final after = await bogey();
      expect(after.bogeyPressure, before.bogeyPressure);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
