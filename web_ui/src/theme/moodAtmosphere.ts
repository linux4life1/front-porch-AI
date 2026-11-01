// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Mood on the character on the web: the same maths as
// lib/services/chat/mood_atmosphere.dart (strength by intensity and hold,
// a need in trouble, the ring's weight from trust, the bond halo) and the
// same label-to-tone table as mood_physics.dart. The colours come on the
// chat state (`moodPaints`, from RealismColors.moodPaintsWire); this file
// never names one.

import type { ThemeMode } from './appTheme';

export type MoodTone = 'sour' | 'low' | 'anxious' | 'lifted' | 'warm' | 'charged';

/** mood_physics.dart `_toneByCanonical`. */
const TONE_BY_LABEL: Record<string, MoodTone> = {
  anger: 'sour', annoyance: 'sour', disgust: 'sour', disapproval: 'sour',
  sadness: 'low', grief: 'low', disappointment: 'low', remorse: 'low',
  fear: 'anxious', nervousness: 'anxious', confusion: 'anxious', embarrassment: 'anxious',
  joy: 'lifted', amusement: 'lifted', excitement: 'lifted', optimism: 'lifted', pride: 'lifted',
  relief: 'lifted', gratitude: 'lifted', admiration: 'lifted', approval: 'lifted',
  love: 'warm', affection: 'warm', caring: 'warm',
  desire: 'charged', anticipation: 'charged', curiosity: 'charged', surprise: 'charged', realization: 'charged',
};

export function moodToneOf(label: string | null | undefined): MoodTone | null {
  const key = (label ?? '').trim().toLowerCase();
  if (!key || key === 'neutral') return null;
  return TONE_BY_LABEL[key] ?? null;
}

/** mild 1, moderate 2, strong 3; unknown or empty 0. */
export function intensityRank(intensity: string | null | undefined): number {
  switch ((intensity ?? '').trim().toLowerCase()) {
    case 'strong': case 'high': case 'intense': return 3;
    case 'moderate': case 'medium': return 2;
    case 'mild': case 'low': case 'faint': return 1;
    default: return 0;
  }
}

export const STRENGTH_BY_RANK: Record<number, number> = { 1: 0.3, 2: 0.55, 3: 0.85 };
export const HOLD_EASE = 0.08;
export const HOLD_FLOOR = 0.6;
export const STRENGTH_MAX = 1.2;
export const NEED_THROB_AT = 25;
export const NEED_HAMMER_AT = 10;
export const TRUST_HEAVY_FROM = 40;
export const TRUST_BROKEN_BELOW = -10;
export const DRAMA_MIN = 0.4;
export const DRAMA_MAX = 1.6;

export function moodStrength(tone: MoodTone | null, rank: number, held: number, drama: number): number {
  if (!tone) return 0;
  const base = STRENGTH_BY_RANK[Math.min(3, Math.max(1, rank))];
  const ease = Math.min(1, Math.max(HOLD_FLOOR, 1 / (1 + held * HOLD_EASE)));
  return Math.min(STRENGTH_MAX, Math.max(0, base * drama * ease));
}

export interface MoodAtmosphere { tone: MoodTone | null; rank: number; held: number; strength: number; label: string }

export function moodAtmosphereOf(
  label: string | null | undefined, intensity: string | null | undefined, held: number | null | undefined, drama: number,
): MoodAtmosphere {
  const tone = moodToneOf(label);
  const rawRank = intensityRank(intensity);
  const rank = rawRank === 0 ? 1 : rawRank;
  const h = held ?? 0;
  return { tone, rank, held: h, strength: moodStrength(tone, rank, h, drama), label: tone ? (label ?? '').trim().toLowerCase() : '' };
}

export interface NeedTrouble { low: boolean; critical: boolean; inverted: boolean }

/** Below 25 throbs, below 10 hammers; hygiene on a character who enjoys it low inverts. */
export function needTrouble(need: string, level: number, enjoysLowHygiene: boolean): NeedTrouble {
  const inverted = need.toLowerCase() === 'hygiene' && enjoysLowHygiene;
  if (inverted) return { low: level >= 100 - NEED_THROB_AT, critical: level > 100 - NEED_HAMMER_AT, inverted: true };
  return { low: level <= NEED_THROB_AT, critical: level < NEED_HAMMER_AT, inverted: false };
}

export function firstNeedInTrouble(needs: Record<string, number>, enjoysLowHygiene: boolean): string | null {
  for (const [k, v] of Object.entries(needs)) if (needTrouble(k, v, enjoysLowHygiene).low) return k;
  return null;
}

export type RingWeight = 'heavy' | 'settled' | 'broken';
export const ringWeightForTrust = (trust: number): RingWeight =>
  trust >= TRUST_HEAVY_FROM ? 'heavy' : trust >= TRUST_BROKEN_BELOW ? 'settled' : 'broken';

export const bondHalo = (bond: number): { share: number; warm: boolean } =>
  ({ share: Math.min(1, Math.abs(bond) / 100), warm: bond >= 0 });

export type MoodLevel = 'off' | 'portrait' | 'all';

export interface MoodLook { level: MoodLevel; drama: number }

/** The desktop's colours for the mode this page paints. */
export interface MoodPaints { tones: Record<MoodTone, string>; needs: Record<string, string>; haloWarm: string; haloChill: string }

const CSS_COLOUR = /^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$/;
const TONES: MoodTone[] = ['sour', 'low', 'anxious', 'lifted', 'warm', 'charged'];

/** The chat state's Mood on the character, or an off look for an older desktop. */
export function moodLookOf(state: { moodOnCharacter?: unknown; moodDrama?: unknown } | null | undefined): MoodLook {
  const level = state?.moodOnCharacter;
  const drama = state?.moodDrama;
  return {
    level: level === 'portrait' || level === 'all' ? level : 'off',
    drama: typeof drama === 'number' && Number.isFinite(drama) ? Math.min(DRAMA_MAX, Math.max(DRAMA_MIN, drama)) : 1,
  };
}

/** The paints for [mode], or null when the desktop sent none or a broken set. */
export function moodPaintsOf(raw: unknown, mode: ThemeMode): MoodPaints | null {
  if (!raw || typeof raw !== 'object') return null;
  const w = raw as Record<string, unknown>;
  const tones = w.tones as Record<string, unknown> | undefined;
  const m = w[mode] as Record<string, unknown> | undefined;
  if (!tones || typeof tones !== 'object' || !m || typeof m !== 'object') return null;
  const ok = (v: unknown): v is string => typeof v === 'string' && CSS_COLOUR.test(v);
  if (!TONES.every((t) => ok(tones[t])) || !ok(m.haloWarm) || !ok(m.haloChill)) return null;
  const needs = m.needs as Record<string, unknown> | undefined;
  if (!needs || typeof needs !== 'object' || !Object.values(needs).every(ok)) return null;
  return {
    tones: Object.fromEntries(TONES.map((t) => [t, tones[t] as string])) as Record<MoodTone, string>,
    needs: { ...(needs as Record<string, string>) },
    haloWarm: m.haloWarm,
    haloChill: m.haloChill,
  };
}

/** The CSS custom properties a ring, bar or bubble paints from. */
export function moodVars(mood: MoodAtmosphere, paints: MoodPaints, bond: number, trust: number, needHue: string | null): Record<string, string> {
  const halo = bondHalo(bond);
  const vars: Record<string, string> = {
    '--mood-a': mood.strength.toFixed(3),
    '--mood-hue': mood.tone ? paints.tones[mood.tone] : 'transparent',
    '--mood-halo': halo.warm ? paints.haloWarm : paints.haloChill,
    '--mood-halo-share': halo.share.toFixed(3),
    '--mood-ring-w': ringWeightForTrust(trust) === 'heavy' ? '5px' : ringWeightForTrust(trust) === 'settled' ? '3px' : '1.5px',
  };
  if (needHue) vars['--mood-need'] = needHue;
  return vars;
}
