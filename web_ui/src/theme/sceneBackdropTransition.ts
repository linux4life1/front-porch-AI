// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The move from one place's picture to the next, as the timeline the chat
// page plays on its backdrop canvas: the twin of
// lib/services/chat/scene/scene_backdrop_transition.dart, same frame at
// the same share of the move. Fog rolls in and clears on the new place, a
// storm cuts there on a strike, anything else travels: the old place
// drifts off under a sweep of light while the new one settles.

import { flashShape } from './sceneEffectsRender';

export type SceneMoveKind = 'travel' | 'fogRoll' | 'lightningCut';

export function sceneMoveKindFor(condition: string | null | undefined): SceneMoveKind {
  if (condition === 'fog') return 'fogRoll';
  if (condition === 'storm') return 'lightningCut';
  return 'travel';
}

export function sceneMoveDuration(kind: SceneMoveKind): number {
  return kind === 'travel' ? 1.6 : kind === 'fogRoll' ? 2.0 : 0.9;
}

export const SCENE_MOVE_TITLE_IN = 0.25;
export const SCENE_MOVE_TITLE_OUT = 0.8;
export const SCENE_MOVE_STILL_TITLE = 1.6;

export interface SceneMoveFrame {
  outAlpha: number; outScale: number; outDx: number;
  inAlpha: number; inScale: number; inDx: number;
  sweep: number; sweepAlpha: number; cover: number; flash: number; dip: number; title: number;
}

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
export const sceneMoveSpan = (p: number, a: number, b: number) => clamp01((p - a) / (b - a));
export const easeOutCubic = (t: number) => 1 - Math.pow(1 - t, 3);
export const easeInCubic = (t: number) => t * t * t;
export const easeInOutCubic = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export function sceneMoveTitle(p: number): number {
  if (p < SCENE_MOVE_TITLE_IN) return easeOutCubic(sceneMoveSpan(p, 0.1, SCENE_MOVE_TITLE_IN));
  if (p > SCENE_MOVE_TITLE_OUT) return 1 - easeInCubic(sceneMoveSpan(p, SCENE_MOVE_TITLE_OUT, 1));
  return 1;
}

export function sceneMoveFrame(kind: SceneMoveKind, p: number): SceneMoveFrame {
  const t = clamp01(p);
  const title = sceneMoveTitle(t);
  if (kind === 'travel') {
    const out = easeInCubic(sceneMoveSpan(t, 0.15, 0.75));
    const inn = easeOutCubic(sceneMoveSpan(t, 0.2, 0.8));
    const s = sceneMoveSpan(t, 0.25, 0.85);
    return {
      outAlpha: 1 - out, outScale: 1 + 0.06 * easeInOutCubic(t), outDx: -0.02 * easeInOutCubic(t),
      inAlpha: inn, inScale: 1.08 - 0.08 * inn, inDx: 0.02 * (1 - inn),
      sweep: t < 0.25 || t > 0.85 ? -1 : s, sweepAlpha: 0.35 * Math.sin(Math.PI * s),
      cover: 0, flash: 0, dip: 0.2 * Math.sin(Math.PI * t), title,
    };
  }
  if (kind === 'fogRoll') {
    const closing = easeInOutCubic(sceneMoveSpan(t, 0, 0.45));
    const opening = easeInOutCubic(sceneMoveSpan(t, 0.55, 1));
    const cover = t < 0.5 ? closing : 1 - opening;
    const swapped = t >= 0.5;
    const settle = easeOutCubic(sceneMoveSpan(t, 0.5, 1));
    return {
      outAlpha: swapped ? 0 : 1, outScale: 1 + 0.03 * closing, outDx: 0,
      inAlpha: swapped ? 1 : 0, inScale: 1.04 - 0.04 * settle, inDx: 0,
      sweep: -1, sweepAlpha: 0, cover, flash: 0, dip: 0, title,
    };
  }
  const swapped = t >= 0.12;
  const flash = t < 0.6 ? flashShape(1 - t / 0.6) : 0;
  const after = swapped ? 0.25 * (1 - sceneMoveSpan(t, 0.12, 0.5)) : 1;
  const settle = easeOutCubic(sceneMoveSpan(t, 0.12, 1));
  return {
    outAlpha: after, outScale: 1, outDx: 0,
    inAlpha: swapped ? 1 : 0, inScale: 1.03 - 0.03 * settle, inDx: 0,
    sweep: -1, sweepAlpha: 0, cover: 0, flash, dip: 0, title,
  };
}

export interface SceneFogBank { left: boolean; y: number; r: number }

/** Three banks a side from the place's seeded generator. */
export function sceneFogBanks(r: () => number): SceneFogBank[] {
  const banks: SceneFogBank[] = [];
  for (let i = 0; i < 6; i++) banks.push({ left: i % 2 === 0, y: 0.1 + r() * 0.8, r: 0.35 + r() * 0.25 });
  return banks;
}

export function sceneFogBankX(bank: SceneFogBank, cover: number): number {
  return bank.left ? -bank.r + cover * (0.4 + bank.r) : 1 + bank.r - cover * (0.4 + bank.r);
}

export function sceneFogWash(cover: number): number {
  return 0.9 * cover * cover;
}
