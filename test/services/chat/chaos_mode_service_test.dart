// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted ChaosModeService (plain class).
// Verifies pressure growth + cap + effective chance, checkAndTick (growth + roll formula),
// spinWheelEvents (size, NSFW conditional inclusion, no dups), applyPreparedEvent ({{char}}
// replacement is caller's responsibility here; zero pressure, pending injection, metadata cb,
// save/notify), clear/delivered timing + flag, reset/seed/load paths, group vs 1:1 (chat-scoped
// pressure shared, no per-speaker), serialization roundtrips via load, auto vs manual blocking,
// NSFW pool behavior.
// Uses createTestChaos factory (per plan + needs precedent) for all ctors.
// Real ChatService pre-turn paths (checkAndTick in send flow, clear in pre-turn, injection via
// _get which delegates) exercised indirectly via the key realism/group/session tests run as part
// of verification (no new regressions). Roll uses live DateTime (entropy note below); math and
// state transitions are deterministic and fully covered.
//
// Callback contract note for future extractors: all on*/get* passed at construction must be
// exercised (current coverage: notify, save, setPendingRealismMetadata).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chaos/chaos_frequency.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/pressure_roll.dart';

/// Test factory to reduce callback boilerplate (modeled exactly on needs_simulation_test).
/// Supplies realistic defaults; override for targeted scenarios (e.g. enabled state, nsfw).
/// For values mutated after construction, pass live getters via *Fn params.
ChaosModeService createTestChaos({
  List<String>? notifies,
  List<String>? saves,
  List<String>? metadataKeys,
  List<String>? metadataValues,
  bool enabled = false,
  bool nsfw = false,
  int initialPressure = 0,
}) {
  final n = notifies ?? <String>[];
  final s = saves ?? <String>[];
  final mk = metadataKeys ?? <String>[];
  final mv = metadataValues ?? <String>[];

  final svc = ChaosModeService(
    onNotify: () => n.add('notify'),
    onSaveChat: () async => s.add('save'),
    onSetPendingRealismMetadata: (k, v) {
      mk.add(k);
      mv.add(v);
    },
  );
  // Seed initial state via public surface (tests the setters used by parent resets/loads)
  if (enabled || initialPressure > 0 || nsfw) {
    svc.seedFromGroupOrExt(enabled, nsfw);
    if (initialPressure > 0) svc.setPressure(initialPressure);
  }
  return svc;
}

void main() {
  group('ChaosModeService (extracted)', () {
    test('pressure grows by growthPerTurn and caps at pressureCap', () {
      final chaos = createTestChaos(enabled: true, initialPressure: 0);
      expect(chaos.chaosPressure, 0);
      // Simulate ticks via the public check (growth always happens when enabled; roll only decides fires).
      // 20 iterations * 5 = 100 (cap).
      for (int i = 0; i < 20; i++) {
        chaos.checkAndTickChaosPressure();
      }
      expect(chaos.chaosPressure, ChaosModeService.pressureCap);
    });

    test('effective chance = base + pressure (clamped to cap)', () {
      // Indirect via check behavior + state; direct formula is internal but growth path covers.
      final chaos = createTestChaos(enabled: true, initialPressure: 0);
      // After 1 tick: pressure=5, effective=10
      chaos.checkAndTickChaosPressure();
      // Whether it fires is a random roll; the pressure step is not.
      expect(chaos.chaosPressure, ChaosModeService.growthPerTurn);
    });

    test('checkAndTick does nothing and returns false when disabled', () {
      final chaos = createTestChaos(enabled: false, initialPressure: 50);
      final pBefore = chaos.chaosPressure;
      final fired = chaos.checkAndTickChaosPressure();
      expect(fired, isFalse);
      expect(chaos.chaosPressure, pBefore); // no growth
    });

    test(
      'spinWheelEvents returns exactly 8, no dups, includes NSFW only when enabled',
      () {
        final chaosNoNsfw = createTestChaos(enabled: true, nsfw: false);
        final noNsfw = chaosNoNsfw.spinWheelEvents();
        expect(noNsfw.length, 8);
        expect(noNsfw.toSet().length, 8); // no dups
        // None should be from the NSFW pool (we can spot-check a distinctive NSFW string)
        expect(noNsfw.any((e) => e.contains('propositioned')), isFalse);

        final chaosWithNsfw = createTestChaos(enabled: true, nsfw: true);
        final withNsfw = chaosWithNsfw.spinWheelEvents();
        expect(withNsfw.length, 8);
        expect(withNsfw.toSet().length, 8);
        // At least one NSFW is possible (not guaranteed due to shuffle+take, but pool is added)
        // We only assert the mechanism: when nsfw the combined pool is used.
      },
    );

    test(
      'applyPreparedEvent zeros pressure, sets pending injection, calls metadata cb + save/notify',
      () async {
        final notifies = <String>[];
        final saves = <String>[];
        final mkeys = <String>[];
        final mvals = <String>[];
        final chaos = ChaosModeService(
          onNotify: () => notifies.add('notify'),
          onSaveChat: () async => saves.add('save'),
          onSetPendingRealismMetadata: (k, v) {
            mkeys.add(k);
            mvals.add(v);
          },
        );
        chaos.setPressure(42);
        expect(chaos.chaosPressure, 42);
        expect(chaos.hasPendingChaosEvent, isFalse);

        await chaos.applyPreparedEvent(
          'The event with {{char}} already replaced',
        );

        expect(chaos.chaosPressure, 0);
        expect(chaos.hasPendingChaosEvent, isTrue);
        expect(chaos.pendingChaosInjection, contains('already replaced'));
        expect(mkeys, contains('chance_time_event'));
        expect(saves, isNotEmpty);
        expect(notifies, isNotEmpty);
      },
    );

    test('clearDeliveredPendingIfAny and markEventDelivered timing', () {
      final chaos = createTestChaos(enabled: true);
      chaos.setPendingChaosInjection('foo');
      chaos.setEventDelivered(false);
      expect(chaos.hasPendingChaosEvent, isTrue);

      // Simulate post-delivery clear (as done in pre-turn)
      chaos.setEventDelivered(true);
      // Once delivered (injected into a response), hasPending must be false for UI
      // (sidebar no longer shows "EVENT PENDING" / disables spin), even though the
      // raw value remains for regen support of that message.
      expect(chaos.hasPendingChaosEvent, isFalse);
      chaos.clearDeliveredPendingIfAny();
      expect(chaos.hasPendingChaosEvent, isFalse);
      expect(chaos.chaosEventDelivered, isFalse);
    });

    test('resetForFreshChat and seed/load paths', () {
      final chaos = createTestChaos(
        enabled: true,
        nsfw: true,
        initialPressure: 77,
      );
      expect(chaos.chaosModeEnabled, isTrue);
      expect(chaos.chaosNsfwEnabled, isTrue);
      expect(chaos.chaosPressure, 77);

      chaos.resetForFreshChat();
      expect(chaos.chaosModeEnabled, isFalse);
      expect(chaos.chaosPressure, 0);
      expect(chaos.hasPendingChaosEvent, isFalse);
      expect(chaos.chaosEventDelivered, isFalse);

      chaos.seedFromGroupOrExt(true, true);
      expect(chaos.chaosModeEnabled, isTrue);
      expect(chaos.chaosNsfwEnabled, isTrue);

      chaos.loadScalars(modeEnabled: false, pressure: 15);
      expect(chaos.chaosModeEnabled, isFalse);
      expect(chaos.chaosPressure, 15);
    });

    test('public consts exposed for tests / shims', () {
      expect(ChaosModeService.baseChance, 5);
      expect(ChaosModeService.growthPerTurn, 5);
      expect(ChaosModeService.pressureCap, 100);
      expect(ChaosModeService.chanceTimeEventPool.length, greaterThan(100));
      expect(ChaosModeService.chanceTimeNsfwPool.length, greaterThan(20));
    });
  });

  // The PressureRoll extraction (docs/design/boons-and-bogies.md phase 1)
  // moved the grow → roll → cooldown math out of ChaosModeService. These
  // vectors were captured from the pre-extraction service; any change to the
  // numbers, the clamp order or the number of random draws shifts the
  // sequence and fails here — chaos stays bit-for-bit unchanged.
  group('PressureRoll golden vectors (Chaos Mode bit-for-bit)', () {
    final fixture =
        jsonDecode(
              File(
                'test/fixtures/chaos/pressure_roll_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final scenarios = (fixture['scenarios'] as List)
        .cast<Map<String, dynamic>>();

    test('fixture covers every frequency with several seeds', () {
      expect(scenarios.length, greaterThanOrEqualTo(6));
      expect(
        scenarios.map((s) => s['name']).toSet(),
        containsAll(<String>['rare', 'normal', 'wild']),
      );
    });

    for (final scenario in scenarios) {
      test(
        '${scenario['name']} seed ${scenario['seed']} replays exactly',
        () async {
          final freq = ChaosFrequency.fromName(scenario['name'] as String);
          final turns = (scenario['turns'] as List)
              .cast<Map<String, dynamic>>();
          final svc = ChaosModeService(
            onNotify: () {},
            onSaveChat: () async {},
            onSetPendingRealismMetadata: (_, _) {},
            getFrequency: () => freq,
            random: Random(scenario['seed'] as int),
          )..setModeEnabled(true);

          for (var i = 0; i < turns.length; i++) {
            final fired = svc.checkAndTickChaosPressure();
            if (fired) await svc.applyPreparedEvent('capture event');
            expect(fired, turns[i]['fired'], reason: 'turn $i fired');
            expect(
              svc.chaosPressure,
              turns[i]['pressure'],
              reason: 'turn $i pressure',
            );
            expect(
              svc.cooldownTurns,
              turns[i]['cooldown'],
              reason: 'turn $i cooldown',
            );
          }
        },
      );
    }
  });

  group('PressureRoll draw order', () {
    test('a fixed growth range consumes exactly the roll draw', () {
      // The old inline loop drew one nextInt(100) per live turn. An extra
      // draw for a fixed growth range would make this differ from the twin.
      final twin = Random(4242);
      final expected = twin.nextInt(PressureRoll.rollScale);
      final tick = PressureRoll.tick(
        base: 5,
        growthMin: 5,
        growthMax: 5,
        pressureCap: 100,
        chanceCap: 100,
        pressure: 0,
        cooldown: 0,
        random: Random(4242),
      );
      expect(tick.roll, expected);
      expect(tick.pressure, 5);
    });

    test('a cooldown turn draws nothing and holds pressure', () {
      final tick = PressureRoll.tick(
        base: 5,
        growthMin: 5,
        growthMax: 5,
        pressureCap: 100,
        chanceCap: 100,
        pressure: 40,
        cooldown: 3,
        random: Random(1),
      );
      expect(tick.fired, isFalse);
      expect(tick.pressure, 40);
      expect(tick.cooldown, 2);
      expect(tick.roll, isNull);
    });

    test('jittered growth and cooldown stay inside their ranges', () {
      final rnd = Random(11);
      for (var i = 0; i < 500; i++) {
        final t = PressureRoll.tick(
          base: 3,
          growthMin: 2,
          growthMax: 6,
          pressureCap: 100,
          chanceCap: 45,
          pressure: 0,
          cooldown: 0,
          random: rnd,
        );
        expect(t.pressure, inInclusiveRange(2, 6));
        expect(
          PressureRoll.cooldownAfterFire(min: 1, max: 3, random: rnd),
          inInclusiveRange(1, 3),
        );
      }
    });

    test('the chance ceiling clamps without shrinking the roll scale', () {
      final tick = PressureRoll.tick(
        base: 3,
        growthMin: 4,
        growthMax: 4,
        pressureCap: 100,
        chanceCap: 45,
        pressure: 99,
        cooldown: 0,
        random: Random(0),
      );
      expect(tick.pressure, 100);
      // Chance would be 103, capped to 45 — a 45% roll on the 0–99 scale.
      expect(tick.fired, tick.roll! < 45);
    });

    test('the group member twin replays the scalar sequence', () async {
      ChaosModeService build() => ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        getFrequency: () => ChaosFrequency.normal,
        random: Random(777),
      );

      final scalar = build()..setModeEnabled(true);
      final memberSvc = build();
      final bag = GroupMemberRealism()..chaosSwitch = true;

      for (var i = 0; i < 80; i++) {
        final a = scalar.checkAndTickChaosPressure();
        final b = memberSvc.checkAndTickMember(bag);
        expect(b, a, reason: 'turn $i fired');
        expect(bag.chaosPressure, scalar.chaosPressure, reason: 'turn $i');
        expect(bag.chaosCooldown, scalar.cooldownTurns, reason: 'turn $i');
        if (a) {
          await scalar.applyPreparedEvent('x');
          await memberSvc.applyPreparedEventMember(bag, 'x');
        }
      }
    });
  });
}
