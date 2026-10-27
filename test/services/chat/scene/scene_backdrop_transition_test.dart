// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The move from one place's picture to the next
// (scene_backdrop_transition.dart, twinned in sceneBackdropTransition.ts):
// the weather picks the move, each move's frames are pinned at a few
// shares so both surfaces play the same thing, the fog closes fully at the
// middle of its roll and the swap hides under it, and the strike swaps on
// its first peak.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/scene/scene_backdrop_transition.dart';
import 'package:front_porch_ai/services/chat/scene/scene_rng.dart';

void main() {
  test('the weather picks the move', () {
    expect(sceneMoveKindFor('fog'), SceneMoveKind.fogRoll);
    expect(sceneMoveKindFor('storm'), SceneMoveKind.lightningCut);
    for (final c in ['clear', 'cloudy', 'overcast', 'rain', 'snow', null]) {
      expect(sceneMoveKindFor(c), SceneMoveKind.travel, reason: '$c');
    }
    expect(sceneMoveDuration(SceneMoveKind.travel), 1.6);
    expect(sceneMoveDuration(SceneMoveKind.fogRoll), 2.0);
    expect(sceneMoveDuration(SceneMoveKind.lightningCut), 0.9);
  });

  test(
    'travel: the old place drifts off under the sweep as the new settles',
    () {
      final start = sceneMoveFrame(SceneMoveKind.travel, 0);
      expect(start.outAlpha, 1);
      expect(start.inAlpha, 0);
      expect(start.inScale, closeTo(1.08, 1e-9));
      expect(start.sweep, -1, reason: 'no sweep yet');
      final mid = sceneMoveFrame(SceneMoveKind.travel, 0.5);
      expect(
        mid.outAlpha,
        closeTo(1 - 0.5833333 * 0.5833333 * 0.5833333, 1e-6),
      );
      expect(mid.inAlpha, closeTo(0.875, 1e-9));
      expect(mid.outScale, closeTo(1.03, 1e-9));
      expect(mid.outDx, closeTo(-0.01, 1e-9));
      expect(mid.inDx, closeTo(0.0025, 1e-9));
      expect(mid.sweep, closeTo(0.4166667, 1e-6));
      expect(mid.sweepAlpha, greaterThan(0.3));
      expect(mid.dip, closeTo(0.2, 1e-9));
      expect(mid.cover, 0);
      expect(mid.flash, 0);
      final end = sceneMoveFrame(SceneMoveKind.travel, 1);
      expect(end.outAlpha, 0);
      expect(end.inAlpha, 1);
      expect(end.inScale, closeTo(1, 1e-9));
      expect(end.inDx, closeTo(0, 1e-9));
      expect(end.sweep, -1);
      expect(end.dip, closeTo(0, 1e-9));
      expect(
        sceneMoveFrame(SceneMoveKind.travel, 2).inAlpha,
        1,
        reason: 'clamped',
      );
    },
  );

  test(
    'fog roll: closed at the middle, the swap under it, clear at the end',
    () {
      final closing = sceneMoveFrame(SceneMoveKind.fogRoll, 0.25);
      expect(closing.cover, closeTo(0.6488, 1e-3));
      expect(closing.outAlpha, 1);
      expect(closing.inAlpha, 0);
      final closed = sceneMoveFrame(SceneMoveKind.fogRoll, 0.5);
      expect(closed.cover, 1);
      expect(closed.outAlpha, 0, reason: 'swapped under the fog');
      expect(closed.inAlpha, 1);
      expect(sceneMoveFrame(SceneMoveKind.fogRoll, 0.47).cover, 1);
      expect(sceneMoveFrame(SceneMoveKind.fogRoll, 0.53).cover, 1);
      final end = sceneMoveFrame(SceneMoveKind.fogRoll, 1);
      expect(end.cover, closeTo(0, 1e-9));
      expect(end.inScale, closeTo(1, 1e-9));
      expect(sceneFogWash(1), 0.9);
      expect(sceneFogWash(0.5), closeTo(0.225, 1e-9));
    },
  );

  test(
    'lightning cut: swaps on the first peak, lights twice, keeps an after-image',
    () {
      final before = sceneMoveFrame(SceneMoveKind.lightningCut, 0.05);
      expect(before.outAlpha, 1);
      expect(before.inAlpha, 0);
      expect(before.flash, 1, reason: 'the first strike');
      final at = sceneMoveFrame(SceneMoveKind.lightningCut, 0.12);
      expect(at.inAlpha, 1);
      expect(at.outAlpha, closeTo(0.25, 1e-9), reason: 'the after-image');
      expect(
        sceneMoveFrame(SceneMoveKind.lightningCut, 0.2).flash,
        0.15,
        reason: 'the dark beat',
      );
      expect(
        sceneMoveFrame(SceneMoveKind.lightningCut, 0.3).flash,
        0.85,
        reason: 'the second strike',
      );
      expect(
        sceneMoveFrame(SceneMoveKind.lightningCut, 0.5).outAlpha,
        closeTo(0, 1e-9),
      );
      expect(sceneMoveFrame(SceneMoveKind.lightningCut, 0.7).flash, 0);
      expect(
        sceneMoveFrame(SceneMoveKind.lightningCut, 1).inScale,
        closeTo(1, 1e-9),
      );
    },
  );

  test('the name shows by a quarter of the move and goes by its end', () {
    expect(sceneMoveTitle(0), 0);
    expect(sceneMoveTitle(0.1), 0);
    expect(sceneMoveTitle(0.25), 1);
    expect(sceneMoveTitle(0.5), 1);
    expect(sceneMoveTitle(0.8), 1);
    expect(sceneMoveTitle(0.9), closeTo(0.875, 1e-9));
    expect(sceneMoveTitle(1), 0);
    for (final k in SceneMoveKind.values) {
      expect(sceneMoveFrame(k, 0.5).title, 1, reason: '$k');
    }
  });

  test('the fog banks come from the place\'s seed, three a side', () {
    final banks = sceneFogBanks(Mulberry32(fnv1a32('tea-rooms')).next);
    expect(banks, hasLength(6));
    expect(banks.where((b) => b.left), hasLength(3));
    expect(banks, sceneFogBanks(Mulberry32(fnv1a32('tea-rooms')).next));
    expect(banks, isNot(sceneFogBanks(Mulberry32(fnv1a32('square')).next)));
    for (final b in banks) {
      expect(b.y, inInclusiveRange(0.1, 0.9));
      expect(b.r, inInclusiveRange(0.35, 0.6));
      expect(
        sceneFogBankX(b, 0),
        b.left ? -b.r : 1 + b.r,
        reason: 'off its edge',
      );
      expect(
        sceneFogBankX(b, 1),
        closeTo(b.left ? 0.4 : 0.6, 1e-9),
        reason: 'past the middle',
      );
    }
  });
}
