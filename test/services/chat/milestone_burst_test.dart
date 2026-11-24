// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The milestone celebration sim (docs/design/boons-and-bogies.md §7, ruling
// 12 as amended): the Dart side of the shared vectors its web twin
// (web_ui/src/theme/milestoneBurst.ts) is pinned to as well.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/milestone_burst.dart';

final Map<String, dynamic> _vectors =
    jsonDecode(
          File(
            'test/fixtures/growth/milestone_burst_vectors.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Matcher _near(num v) => closeTo(v, 1e-9);

void main() {
  test('the sim reproduces the shared vectors, frame for frame', () {
    expect(
      burstSeedFor(_vectors['momentId'] as String),
      _vectors['momentSeed'],
    );
    for (final run in (_vectors['runs'] as List).cast<Map<String, dynamic>>()) {
      final kind = BurstKind.values.byName(run['kind'] as String);
      final burst = MilestoneBurst.plan(kind, run['seed'] as int);
      final why = '${run['kind']} seed ${run['seed']}';
      expect(burst.particles.length, run['count'], reason: why);
      expect(burst.duration, _near(run['duration'] as num), reason: why);
      for (final f in (run['frames'] as List).cast<Map<String, dynamic>>()) {
        burst.stepTo(f['frame'] as int);
        final at = '$why frame ${f['frame']}';
        expect(
          burst.particles.fold<double>(0, (s, p) => s + p.alpha),
          _near(f['alphaSum'] as num),
          reason: at,
        );
        final want = (f['particles'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < want.length; i++) {
          final p = burst.particles[i];
          expect(p.shape.name, want[i]['shape'], reason: at);
          expect(p.color, want[i]['color'], reason: at);
          for (final k in ['x', 'y', 'size', 'rot', 'alpha']) {
            final got = switch (k) {
              'x' => p.x,
              'y' => p.y,
              'size' => p.size,
              'rot' => p.rot,
              _ => p.alpha,
            };
            expect(got, _near(want[i][k] as num), reason: '$at #$i $k');
          }
        }
      }
    }
  });

  test('every kind starts dark, ends dark, and finishes within 3.5 s', () {
    for (final kind in BurstKind.values) {
      final burst = MilestoneBurst.plan(kind, 4242);
      expect(
        burst.particles.every((p) => p.alpha == 0),
        isTrue,
        reason: '$kind',
      );
      expect(burst.duration, lessThan(3.5), reason: '$kind');
      burst.stepTo((burst.duration / kBurstDt).ceil() + 1);
      expect(burst.done, isTrue);
      expect(burst.particles.every((p) => p.alpha == 0), isTrue);
      for (final p in burst.particles) {
        expect(p.alpha, inInclusiveRange(0, 1));
      }
    }
  });

  test('the same moment replays the same burst; another differs', () {
    final a = MilestoneBurst.plan(BurstKind.overcome, burstSeedFor('m1'))
      ..stepTo(40);
    final b = MilestoneBurst.plan(BurstKind.overcome, burstSeedFor('m1'))
      ..stepTo(40);
    final c = MilestoneBurst.plan(BurstKind.overcome, burstSeedFor('m2'))
      ..stepTo(40);
    expect(a.particles.first.x, b.particles.first.x);
    expect(a.particles.first.x, isNot(c.particles.first.x));
  });

  test('every wire kind has a celebration', () {
    for (final wire in [
      'new_boon',
      'new_bogey',
      'master_boon',
      'master_bogey',
      'overcome',
    ]) {
      expect(burstKindForWire(wire), isNotNull, reason: wire);
    }
  });
}
