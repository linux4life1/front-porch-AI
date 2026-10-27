// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The move from one place's picture to the next (sceneBackdropTransition.ts,
// the desktop's scene_backdrop_transition.dart): the same frames at the
// same shares as the Dart test pins, so both surfaces play the same move.

import { describe, expect, it } from 'vitest';
import { mulberry32 } from './sceneEffects';
import {
  sceneFogBankX, sceneFogBanks, sceneFogWash, sceneMoveDuration, sceneMoveFrame, sceneMoveKindFor, sceneMoveTitle,
} from './sceneBackdropTransition';

describe('scene move timeline', () => {
  it('the weather picks the move', () => {
    expect(sceneMoveKindFor('fog')).toBe('fogRoll');
    expect(sceneMoveKindFor('storm')).toBe('lightningCut');
    for (const c of ['clear', 'cloudy', 'rain', 'snow', null, undefined]) expect(sceneMoveKindFor(c)).toBe('travel');
    expect([sceneMoveDuration('travel'), sceneMoveDuration('fogRoll'), sceneMoveDuration('lightningCut')]).toEqual([1.6, 2.0, 0.9]);
  });

  it('travel: the old place drifts off under the sweep as the new settles', () => {
    const start = sceneMoveFrame('travel', 0);
    expect(start.outAlpha).toBe(1);
    expect(start.inAlpha).toBe(0);
    expect(start.inScale).toBeCloseTo(1.08, 9);
    expect(start.sweep).toBe(-1);
    const mid = sceneMoveFrame('travel', 0.5);
    expect(mid.outAlpha).toBeCloseTo(1 - 0.5833333 ** 3, 5);
    expect(mid.inAlpha).toBeCloseTo(0.875, 9);
    expect(mid.outScale).toBeCloseTo(1.03, 9);
    expect(mid.outDx).toBeCloseTo(-0.01, 9);
    expect(mid.inDx).toBeCloseTo(0.0025, 9);
    expect(mid.sweep).toBeCloseTo(0.4166667, 5);
    expect(mid.dip).toBeCloseTo(0.2, 9);
    const end = sceneMoveFrame('travel', 1);
    expect(end.outAlpha).toBe(0);
    expect(end.inAlpha).toBe(1);
    expect(end.sweep).toBe(-1);
  });

  it('fog roll: closed at the middle with the swap under it', () => {
    expect(sceneMoveFrame('fogRoll', 0.25).cover).toBeCloseTo(0.6488, 3);
    const closed = sceneMoveFrame('fogRoll', 0.5);
    expect(closed.cover).toBe(1);
    expect(closed.outAlpha).toBe(0);
    expect(closed.inAlpha).toBe(1);
    expect(sceneMoveFrame('fogRoll', 1).cover).toBeCloseTo(0, 9);
    expect(sceneFogWash(0.5)).toBeCloseTo(0.225, 9);
  });

  it('lightning cut: swaps on the first peak, lights twice, keeps an after-image', () => {
    expect(sceneMoveFrame('lightningCut', 0.05).flash).toBe(1);
    expect(sceneMoveFrame('lightningCut', 0.05).inAlpha).toBe(0);
    const at = sceneMoveFrame('lightningCut', 0.12);
    expect(at.inAlpha).toBe(1);
    expect(at.outAlpha).toBeCloseTo(0.25, 9);
    expect(sceneMoveFrame('lightningCut', 0.2).flash).toBe(0.15);
    expect(sceneMoveFrame('lightningCut', 0.3).flash).toBe(0.85);
    expect(sceneMoveFrame('lightningCut', 0.7).flash).toBe(0);
  });

  it('the name shows by a quarter of the move and goes by its end', () => {
    expect([0, 0.1, 0.25, 0.5, 0.8, 1].map(sceneMoveTitle)).toEqual([0, 0, 1, 1, 1, 0]);
    expect(sceneMoveTitle(0.9)).toBeCloseTo(0.875, 9);
  });

  it('the fog banks come from the seed, three a side', () => {
    const banks = sceneFogBanks(mulberry32(42));
    expect(banks).toHaveLength(6);
    expect(banks.filter((b) => b.left)).toHaveLength(3);
    expect(banks).toEqual(sceneFogBanks(mulberry32(42)));
    for (const b of banks) {
      expect(sceneFogBankX(b, 0)).toBeCloseTo(b.left ? -b.r : 1 + b.r, 9);
      expect(sceneFogBankX(b, 1)).toBeCloseTo(b.left ? 0.4 : 0.6, 9);
    }
  });
});
