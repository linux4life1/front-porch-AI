// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Realism Engine + Needs Simulation form model — the web mirror of the
// Flutter FrontPorchExtensions seeds. The field names match the web API payload
// (and the Dart realism_extensions_json helper) verbatim so a draft flows
// straight into /api/characters/create|update and back out of /detail's
// `realism` block with no intermediate mapping. Consumed by RealismFormSection
// and NeedsFormSection, which are reused by character create + edit.

export interface RealismValues {
  realismEnabled: boolean;
  timeOfDay: string;
  dayCount: number;
  shortTermBond: number;
  longTermBond: number;
  trustLevel: number;
  characterEmotion: string;
  emotionIntensity: string;
  nsfwCooldownEnabled: boolean;
  passageOfTimeEnabled: boolean;
  chaosModeEnabled: boolean;
  currentTask: string;
  realismVerificationEnabled: boolean;
  realismVerificationMaxReprocesses: number;
  realismVerificationStrictness: number;
  realismNeedsDirectorAuthority: boolean;
  // Needs Simulation
  needsSimEnabled: boolean;
  enjoysLowHygiene: boolean;
  needsSimStrength: number;
  needsBaselineHunger: number;
  needsBaselineBladder: number;
  needsBaselineEnergy: number;
  needsBaselineSocial: number;
  needsBaselineFun: number;
  needsBaselineHygiene: number;
  needsBaselineComfort: number;
  needsDecayHunger: number;
  needsDecayBladder: number;
  needsDecayEnergy: number;
  needsDecaySocial: number;
  needsDecayFun: number;
  needsDecayHygiene: number;
  needsDecayComfort: number;
}

/** Defaults mirror Flutter FrontPorchExtensions() exactly. */
export const REALISM_DEFAULTS: RealismValues = {
  realismEnabled: false,
  timeOfDay: 'morning',
  dayCount: 1,
  shortTermBond: 0,
  longTermBond: 0,
  trustLevel: 0,
  characterEmotion: '',
  emotionIntensity: 'mild',
  nsfwCooldownEnabled: false,
  passageOfTimeEnabled: true,
  chaosModeEnabled: false,
  currentTask: '',
  realismVerificationEnabled: false,
  realismVerificationMaxReprocesses: 1,
  realismVerificationStrictness: 3,
  realismNeedsDirectorAuthority: false,
  needsSimEnabled: false,
  enjoysLowHygiene: false,
  needsSimStrength: 1,
  needsBaselineHunger: 80,
  needsBaselineBladder: 80,
  needsBaselineEnergy: 80,
  needsBaselineSocial: 80,
  needsBaselineFun: 80,
  needsBaselineHygiene: 80,
  needsBaselineComfort: 80,
  needsDecayHunger: 4,
  needsDecayBladder: 6,
  needsDecayEnergy: 3,
  needsDecaySocial: 2,
  needsDecayFun: 2,
  needsDecayHygiene: 1,
  needsDecayComfort: 2,
};

export const TIME_OPTIONS = [
  'dawn',
  'morning',
  'late_morning',
  'afternoon',
  'evening',
  'night',
];

export const INTENSITY_OPTIONS = ['mild', 'moderate', 'strong'];

export function titleCase(value: string): string {
  return value
    .split('_')
    .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
    .join(' ');
}

/** Coerce the /detail `realism` block (or null) into a full RealismValues,
 *  filling any missing key with its desktop default. */
export function realismFromDetail(raw: Partial<RealismValues> | null | undefined): RealismValues {
  return { ...REALISM_DEFAULTS, ...(raw ?? {}) };
}

// ── Relationship tier names (mirror realism_form_section.dart) ──────────────
export function shortTermTier(score: number): string {
  if (score >= 80) return 'Devoted';
  if (score >= 50) return 'Affectionate';
  if (score >= 20) return 'Warm';
  if (score >= 5) return 'Friendly';
  if (score >= -4) return 'Neutral';
  if (score >= -19) return 'Cool';
  if (score >= -49) return 'Distant';
  if (score >= -79) return 'Hostile';
  return 'Despised';
}

export function longTermTier(score: number): string {
  if (score >= 80) return 'Soulbound';
  if (score >= 50) return 'Deep Bond';
  if (score >= 20) return 'Close';
  if (score >= 5) return 'Familiar';
  if (score >= -4) return 'Acquaintance';
  if (score >= -19) return 'Uneasy';
  if (score >= -49) return 'Estranged';
  if (score >= -79) return 'Broken';
  return 'Nemesis';
}

export function trustTier(level: number): string {
  if (level >= 80) return 'Absolute Trust';
  if (level >= 50) return 'Deep Trust';
  if (level >= 20) return 'Trusting';
  if (level >= 5) return 'Cautious Trust';
  if (level >= -4) return 'Neutral';
  if (level >= -19) return 'Wary';
  if (level >= -49) return 'Suspicious';
  if (level >= -79) return 'Paranoid';
  return 'Absolute Distrust';
}

/** Decay-rate description (mirror needs_form_section.dart). */
export function decayDescription(v: number): string {
  if (v === 0) return `Static (0)`;
  if (v <= 2) return `Very Slow (${v})`;
  if (v <= 4) return `Slow (${v})`;
  if (v <= 7) return `Normal (${v})`;
  if (v <= 12) return `Fast (${v})`;
  return `Very Fast (${v})`;
}
