// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Realism Engine + Needs Simulation form model — the web mirror of the
// Flutter FrontPorchExtensions seeds. The field names match the web API payload
// (and the Dart realism_extensions_json helper) verbatim so a draft flows
// straight into /api/characters/create|update and back out of /detail's
// `realism` block with no intermediate mapping. Consumed by RealismFormSection
// and NeedsFormSection, which are reused by character create + edit.

import { parseWorkDaysField } from './workHours';

/** One thing a character has: a bare name, or a name plus its condition. */
export type InventoryEntry = string | { name: string; state?: string };

/** Starting Pockets & Wardrobe, as the Dart `FrontPorchExtensions.inventory`
 *  map: `{worn: [...], carrying: [...]}`, either key optional. */
export interface InventoryRecord {
  worn?: InventoryEntry[];
  carrying?: InventoryEntry[];
}

/** Recovery profile — the card's "how it comes down after climax" setting,
 *  the Dart `FrontPorchExtensions.recovery` object (recovery overhaul PR 2;
 *  `RecoveryProfile` in lib/models/character/recovery_profile.dart is the
 *  source of truth — same mirror precedent as the tier names and the pocket
 *  chip text, for the same reason: the browser cannot call Dart, and phone
 *  and desktop must put the identical pair on the card). */
export type RecoveryMode = 'auto' | 'hard' | 'soft';

/** Post-coital dysphoria dial (recovery overhaul PR 8) — mirror of the
 *  Dart `kPcdMood*` constants. Opt-in: absence reads `off`, so a card
 *  saved before PR 8 never rolls the grey beat. */
export type PcdMood = 'off' | 'rare' | 'sometimes';

export interface RecoveryProfileValue {
  recoveryMode: RecoveryMode;
  recoveryMinutes: number | null;
  pcdMood?: PcdMood;
}

/** Roll rates per dial — mirror of kPcdRateRare/kPcdRateSometimes. */
export const PCD_RATE_RARE = 0.15;
export const PCD_RATE_SOMETIMES = 0.35;

/** The dial's options — labels byte-identical with Dart `kPcdOptions`. */
export interface PcdOptionValue {
  key: PcdMood;
  label: string;
}

export const PCD_OPTIONS: PcdOptionValue[] = [
  { key: 'off', label: 'Off' },
  { key: 'rare', label: 'Rare — a grey drift after some climaxes (~15%)' },
  { key: 'sometimes', label: 'Sometimes — often a grey drift after (~35%)' },
];

export const RECOVERY_MIN_MINUTES = 0;
export const RECOVERY_MAX_MINUTES = 180;
/** One reply with the clock off (refractory.dart's kRefractoryMinutesPerTurn). */
export const RECOVERY_MINUTES_PER_REPLY = 15;

/** Decision 3's preset table — keep byte-identical with kRecoveryPresets. */
export interface RecoveryPresetValue {
  key: string;
  label: string;
  recoveryMode: RecoveryMode;
  recoveryMinutes: number | null;
}

export const RECOVERY_PRESETS: RecoveryPresetValue[] = [
  { key: 'auto', label: 'Auto — judge + physiology decide', recoveryMode: 'auto', recoveryMinutes: null },
  { key: 'none', label: 'None / multiorgasmic', recoveryMode: 'soft', recoveryMinutes: null },
  { key: 'personality', label: 'Lock, length by personality', recoveryMode: 'hard', recoveryMinutes: null },
  { key: 'short', label: 'Short (30)', recoveryMode: 'hard', recoveryMinutes: 30 },
  { key: 'typical', label: 'Typical (90)', recoveryMode: 'hard', recoveryMinutes: 90 },
  { key: 'long', label: 'Long (180)', recoveryMode: 'hard', recoveryMinutes: 180 },
  { key: 'custom', label: 'Custom', recoveryMode: 'hard', recoveryMinutes: null },
];

/** Lenient structured-sex read (mirror of `normalizeCharacterSex`; they
 *  first, female before masculine so "female" is not swallowed by "male"). */
export function normalizeSex(raw: unknown): string {
  const s = String(raw ?? '').trim().toLowerCase();
  if (!s) return '';
  const has = (words: string[]) =>
    words.some((w) => new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(s));
  if (has(['they', 'them', 'nonbinary', 'non-binary', 'non binary', 'enby', 'nb', 'genderfluid', 'agender', 'genderless', 'asexual', 'ace', 'futanari', 'futa', 'shapeshifter', 'shapechanger', 'herm'])) return 'other';
  if (has(['female', 'woman', 'women', 'girl', 'lady', 'feminine', 'she', 'her', 'f'])) return 'female';
  if (has(['male', 'man', 'men', 'boy', 'guy', 'masculine', 'he', 'him', 'm'])) return 'male';
  return 'other';
}

/** Coerce the `/detail` `recovery` object (or absence) to a valid profile:
 *  junk mode reads auto, an out-of-span length clamps, and a length on a
 *  non-hard mode is dropped — the pair is one unit, the menu must not lie. */
export function recoveryFromDetail(raw: unknown): RecoveryProfileValue {
  const pcdRaw =
    raw != null && typeof raw === 'object' && typeof (raw as Record<string, unknown>).pcdMood === 'string'
      ? String((raw as Record<string, unknown>).pcdMood).trim().toLowerCase()
      : '';
  const pcdMood: PcdMood = pcdRaw === 'rare' || pcdRaw === 'sometimes' ? (pcdRaw as PcdMood) : 'off';
  if (raw == null || typeof raw !== 'object') return { recoveryMode: 'auto', recoveryMinutes: null, pcdMood };
  const v = raw as Record<string, unknown>;
  const mode: RecoveryMode = v.recoveryMode === 'hard' || v.recoveryMode === 'soft' ? v.recoveryMode : 'auto';
  if (mode !== 'hard') return { recoveryMode: mode, recoveryMinutes: null, pcdMood };
  const n = typeof v.recoveryMinutes === 'number' ? v.recoveryMinutes : Number.parseInt(String(v.recoveryMinutes ?? ''), 10);
  if (!Number.isFinite(n) || n < RECOVERY_MIN_MINUTES) return { recoveryMode: mode, recoveryMinutes: null, pcdMood };
  return { recoveryMode: mode, recoveryMinutes: Math.min(n, RECOVERY_MAX_MINUTES), pcdMood };
}

export function recoveryPresetKey(p: RecoveryProfileValue): string {
  if (p.recoveryMode === 'soft') return 'none';
  if (p.recoveryMode !== 'hard') return 'auto';
  switch (p.recoveryMinutes) {
    case null: return 'personality';
    case 30: return 'short';
    case 90: return 'typical';
    case 180: return 'long';
    default: return 'custom';
  }
}

/** Preset switch preserves the pcd dial — it is orthogonal to kind and
 *  length (mirror of Dart `fromPreset(key, pcdMood:)`). */
export function recoveryFromPreset(key: string, pcdMood: PcdMood = 'off'): RecoveryProfileValue {
  const p = RECOVERY_PRESETS.find((x) => x.key === key);
  if (!p || p.key === 'custom' || p.key === 'auto') {
    return key === 'auto'
      ? { recoveryMode: 'auto', recoveryMinutes: null, pcdMood }
      : recoveryFromPreset('auto', pcdMood);
  }
  return { recoveryMode: p.recoveryMode, recoveryMinutes: p.recoveryMinutes, pcdMood };
}

/** Moving the slider selects Custom (decision 3); the pcd dial survives. */
export function recoveryWithMinutes(
  current: RecoveryProfileValue,
  minutes: number,
): RecoveryProfileValue {
  return {
    recoveryMode: 'hard',
    recoveryMinutes: Math.max(RECOVERY_MIN_MINUTES, Math.min(RECOVERY_MAX_MINUTES, Math.round(minutes))),
    pcdMood: current.pcdMood ?? 'off',
  };
}

/** The pcd dial's setter — junk normalizes to off (mirror of Dart
 *  `withPcdMood`). */
export function recoveryWithPcdMood(
  current: RecoveryProfileValue,
  mood: string,
): RecoveryProfileValue {
  const m = mood.trim().toLowerCase();
  const pcd: PcdMood = m === 'rare' || m === 'sometimes' ? (m as PcdMood) : 'off';
  return {
    recoveryMode: current.recoveryMode,
    recoveryMinutes: current.recoveryMinutes,
    pcdMood: pcd,
  };
}

export function recoveryResolvesLine(p: RecoveryProfileValue, sex: string): string {
  const kind =
    p.recoveryMode === 'auto'
      ? `Auto → ${
          normalizeSex(sex) === 'female'
            ? 'soft gate (card says female)'
            : normalizeSex(sex) === 'male'
              ? 'hard lock (card says male)'
              : normalizeSex(sex) === 'other'
                ? 'hard lock (sex not female — chosen here to change)'
                : "hard lock (no structured sex — today's behavior)"
        }`
      : p.recoveryMode === 'soft'
        ? 'Soft gate — arousal stays up; a ~15 min tenderness window halves touch gains, and each peak within the hour costs more'
        : 'Hard lock';
  const length =
    p.recoveryMinutes != null
      ? `${p.recoveryMinutes} min fixed (replaces the judge's number)`
      : 'length by the personality judge';
  return `Resolves to: ${kind} — ${length}.`;
}

export function recoveryClockOffHint(minutes: number | null): string {
  if (minutes == null) {
    return "With Passage of Time off, each reply of theirs is 15 minutes — the judge's length becomes that many replies.";
  }
  const replies = Math.ceil(minutes / RECOVERY_MINUTES_PER_REPLY);
  return `With Passage of Time off, ${minutes} min ≈ ${replies} ${replies === 1 ? 'reply' : 'replies'} (15 min per reply).`;
}

/** The soft gate's replacement for the minutes slider and its clock-off hint
 *  (mirror of `recoverySoftGateHint` in recovery_profile.dart — edit one,
 *  edit both): the gate has no length, so the slider hides for 'none' and
 *  this line speaks instead. */
export function recoverySoftGateHint(): string {
  return 'This gate has no length to set — the ~15 min tenderness window is fixed, about one reply of theirs with Passage of Time off.';
}

/** Chargen's preset suggestion from the authored intimacy notes (mirror of
 *  `suggestRecoveryPreset` in recovery_profile.dart — keyword scan, never
 *  applied silently). */
export function suggestRecoveryPresetKey(
  intimateInto: string[],
  intimateNotInto: string[] = [],
): string | null {
  const into = (intimateInto ?? []).join(' · ').toLowerCase();
  const not = (intimateNotInto ?? []).join(' · ').toLowerCase();
  const multi = ['multi-orgasm', 'multi orgasm', 'multiple orgasm', 'insatiable', 'always ready', 'always up for', 'high sex drive', 'high libido', 'very sexual', 'again and again', 'no refractory', 'no cooldown', 'recovers fast', 'recovers quickly', 'recovers in minutes', 'go again', 'endless', 'non-stop', 'nonstop', 'all day long'].some((k) => into.includes(k));
  const reserved = ['slow to warm', 'takes a while', 'takes some time', 'takes me a while', 'low sex drive', 'low libido', 'hardly ever', 'rarely', 'rare ', 'delicate', 'slow burn', 'hard to arouse', 'once in a while', 'after a long', 'easily over', 'quick to fade'].some((k) => into.includes(k) || not.includes(k));
  if (multi && !reserved) return 'none';
  if (reserved && !multi) return 'long';
  return null;
}

export function recoverySuggestionLine(key: string | null): string | null {
  if (!key) return null;
  const p = RECOVERY_PRESETS.find((x) => x.key === key);
  if (!p) return null;
  return `Your intimacy notes read like "${p.label}" may fit them — pick it above if you agree. Any preset except Auto or "Lock, length by personality" overrides the personality judge with a fixed length or a fixed window.`;
}

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
  /**
   * No longer authored anywhere (Ambitions replaced the field in both editors);
   * carried through create/update untouched so an older card's task survives an
   * edit and can still be imported as a starting objective.
   */
  currentTask: string;
  /** Long-term goals, one per chip (approved sketch §4). */
  ambitions: string[];
  /** Short plan-line sentences. Identity like ambitions. */
  planLines: string[];
  /** What they do. Blank is omitted from the card, same as desktop. */
  occupation: string;
  /**
   * What the job actually is. Engine key `occupationBrief` — do not invent
   * a second name. Blank is omitted; missing on /detail keeps the default
   * empty string (today stays today).
   */
  occupationBrief: string;
  /** Clock range the pickers write ("9am–5pm"). Not "mornings". */
  hours: string;
  /**
   * Calendar birthday `YYYY-MM-DD`. Blank is omitted. Feb 29 is rejected.
   */
  birthday: string;
  /**
   * DateTime.weekday ints (1=Mon…7=Sun). `null` = missing = Mon–Fri at
   * derive. `[]` = never at work. Do not default this to [] in the form
   * model or an old card's next save turns every day off.
   */
  workDays: number[] | null;
  // Likes & Dislikes, and the 18+ pair. Flat over this bridge (the Dart side's
  // frontPorchFromFields expects camelCase keys); the CARD nests the intimate
  // pair under intimate_preferences, which is the Dart model's business.
  likes: string[];
  dislikes: string[];
  intimateInto: string[];
  intimateNotInto: string[];
  /**
   * Starting Pockets & Wardrobe. Not authored here — there is no inventory
   * control in this form — but declared and carried for the same reason
   * `currentTask` is: the edit page sends `...rv` wholesale, so a field this
   * model does not know about is a field the next save drops.
   *
   * It did exactly that until now, from the other end: the Dart bridge omitted
   * `inventory` entirely, so editing a character from a phone wiped whatever
   * starting pockets its author had written. Both halves are declared now, and
   * the Dart side additionally falls back to the stored value for any client
   * that omits the key.
   */
  inventory: InventoryRecord;
  /** Structured sex + recovery profile. `sex` has no control in this form
   *  (chargen persists it; the recovery block's "resolves to" line reads
   *  it), so it is declared and carried for the same reason `inventory`
   *  is: the edit page sends `...rv` wholesale, and an undeclared field is
   *  a dropped field. `recovery` is authored by the recovery block. */
  sex: string;
  recovery: RecoveryProfileValue;
  realismVerificationEnabled: boolean;
  realismVerificationMaxReprocesses: number;
  realismVerificationStrictness: number;
  realismNeedsDirectorAuthority: boolean;
  /**
   * Per-character Pockets & Wardrobe. AND-gated with the Porch Life global.
   * Missing / null treats as on so old cards keep working.
   */
  pocketsEnabled: boolean;
  /**
   * How a new chat with this character starts Afterglow (Lust, climax,
   * recovery); each chat keeps its own switch from then on. Missing reads on.
   */
  afterglowEnabled: boolean;
  // Needs Simulation
  needsSimEnabled: boolean;
  enjoysLowHygiene: boolean;
  /** sloth | normal | fast. Scales drops only. */
  needsPace: string;
  /** Need keys this character has turned off. Empty means all are on. */
  needsOff: string[];
  needsBaselineHunger: number;
  needsBaselineBladder: number;
  needsBaselineEnergy: number;
  needsBaselineSocial: number;
  needsBaselineFun: number;
  needsBaselineHygiene: number;
  needsBaselineComfort: number;
  /**
   * Sparse opening-state overlays, parallel to `alternateGreetings`.
   * `null` = this alt still reads the room. `{}` = inherit card defaults.
   */
  greetingSeeds: (GreetingSeed | null)[];
}

/** Sparse per-alt overlay. Absent keys inherit the card-level seed. */
export interface GreetingSeed {
  characterEmotion?: string;
  emotionIntensity?: string;
  shortTermBond?: number;
  longTermBond?: number;
  trustLevel?: number;
  dayCount?: number;
  timeOfDay?: string;
  storyStartDate?: string | null;
  storyStartTime?: string | null;
  currentTask?: string;
  needsBaselineHunger?: number;
  needsBaselineBladder?: number;
  needsBaselineEnergy?: number;
  needsBaselineSocial?: number;
  needsBaselineFun?: number;
  needsBaselineHygiene?: number;
  needsBaselineComfort?: number;
  inventory?: InventoryRecord;
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
  ambitions: [],
  planLines: [],
  occupation: '',
  occupationBrief: '',
  hours: '',
  birthday: '',
  workDays: null,
  likes: [],
  dislikes: [],
  intimateInto: [],
  intimateNotInto: [],
  inventory: {},
  sex: '',
  recovery: { recoveryMode: 'auto', recoveryMinutes: null },
  realismVerificationEnabled: false,
  realismVerificationMaxReprocesses: 1,
  realismVerificationStrictness: 3,
  realismNeedsDirectorAuthority: false,
  // AND-gated with the Porch Life global (default on). A new card that
  // writes false silently vetoes Needs even after the engine is turned on.
  pocketsEnabled: true,
  afterglowEnabled: true,
  needsSimEnabled: true,
  enjoysLowHygiene: false,
  needsPace: 'normal',
  needsOff: [],
  needsBaselineHunger: 80,
  needsBaselineBladder: 80,
  needsBaselineEnergy: 80,
  needsBaselineSocial: 80,
  needsBaselineFun: 80,
  needsBaselineHygiene: 80,
  needsBaselineComfort: 80,
  greetingSeeds: [],
};

// ── Pockets & Wardrobe chip text ───────────────────────────────────────────
// Mirrors PocketItem.display / PocketItem.parseDisplay / Pockets.cardJsonFrom
// in lib/services/chat/pockets.dart, which is the source of truth — same
// precedent as the tier-name helpers below, and for the same reason: the
// browser cannot call Dart, and the desktop and web editors must put the
// identical map on the card.
//
// The chip text is the item as it READS — "sundress (rain-soaked)" — because
// that is already the string the sidebar, the receipts and the prompt all show.

const MAX_ITEM_CHARS = 60;
const MAX_PER_LIST = 8;
const FILLER = new Set(['a', 'an', 'the', 'her', 'his', 'their', 'my', 'your', 'of']);
const EMPTY_WARDROBE = new Set([
  'nothing', 'none', 'nude', 'naked', 'unclothed', 'undressed', 'bare', 'empty',
]);

function isEmptyWardrobeRef(name: string): boolean {
  const toks = name
    .toLowerCase()
    .replace(/[^a-z0-9 ]/g, '')
    .split(' ')
    .filter((t) => t && !FILLER.has(t));
  return toks.length > 0 && toks.every((t) => EMPTY_WARDROBE.has(t));
}

function tidy(s: string): string {
  const t = s.replace(/\s+/g, ' ').trim();
  return t.length <= MAX_ITEM_CHARS ? t : t.slice(0, MAX_ITEM_CHARS).trimEnd();
}

/** One entry as chip text: `name` or `name (state)`. */
function entryToChip(e: InventoryEntry): string {
  if (typeof e === 'string') return tidy(e);
  const name = tidy(e?.name ?? '');
  const state = tidy(e?.state ?? '');
  return state ? `${name} (${state})` : name;
}

/** Chip text back to an entry. Only a trailing `(...)` with both halves
 *  non-empty counts as a condition — "(nothing)" and "keys ()" are names. */
function chipToEntry(raw: string): { name: string; state?: string } | null {
  const s = raw.trim();
  if (!s) return null;
  if (s.endsWith(')')) {
    const open = s.lastIndexOf('(');
    if (open > 0) {
      const name = tidy(s.slice(0, open));
      const state = tidy(s.slice(open + 1, -1));
      if (name && state) return { name, state };
    }
  }
  const name = tidy(s);
  return name ? { name } : null;
}

/** Both lists as chip text — the seed side of the editor. */
export function inventoryToChips(rec: InventoryRecord | null | undefined): {
  worn: string[];
  carrying: string[];
} {
  const list = (v: InventoryEntry[] | undefined) =>
    (Array.isArray(v) ? v : []).slice(0, MAX_PER_LIST).map(entryToChip).filter(Boolean);
  return { worn: list(rec?.worn), carrying: list(rec?.carrying) };
}

/** Chip text back to the card map. Empty when nothing survives, so the card
 *  keeps omitting the key entirely rather than storing an empty record. */
export function chipsToInventory(worn: string[], carrying: string[]): InventoryRecord {
  const list = (v: string[]) =>
    v.slice(0, MAX_PER_LIST).map(chipToEntry).filter((e): e is { name: string; state?: string } => !!e);
  const w = list(worn).filter((e) => !isEmptyWardrobeRef(e.name));
  const c = list(carrying);
  if (!w.length && !c.length) return {};
  return { worn: w, carrying: c };
}

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
  const merged: RealismValues = { ...REALISM_DEFAULTS, ...(raw ?? {}) };
  const present = raw != null && Object.prototype.hasOwnProperty.call(raw, 'workDays');
  merged.workDays = parseWorkDaysField(raw?.workDays, present);
  merged.sex = normalizeSex(raw?.sex ?? '');
  merged.recovery = recoveryFromDetail(raw?.recovery);
  return merged;
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
  if (level >= 5) return 'Warming';
  if (level >= -4) return 'Neutral';
  if (level >= -19) return 'Wary';
  if (level >= -49) return 'Suspicious';
  if (level >= -79) return 'Paranoid';
  return 'Absolute Distrust';
}


/** Drop empty greet rows and their paired seed slots together. */
export function compactGreetingPairs(
  greetings: string[],
  seeds: (GreetingSeed | null)[],
): { greetings: string[]; seeds: (GreetingSeed | null)[] } {
  const n = greetings.length;
  const aligned =
    seeds.length === n
      ? seeds
      : seeds.length > n
        ? seeds.slice(0, n)
        : [...seeds, ...Array<GreetingSeed | null>(n - seeds.length).fill(null)];
  const outG: string[] = [];
  const outS: (GreetingSeed | null)[] = [];
  for (let i = 0; i < n; i++) {
    if (!greetings[i].trim()) continue;
    outG.push(greetings[i]);
    outS.push(aligned[i] ?? null);
  }
  while (outS.length && outS[outS.length - 1] == null) outS.pop();
  return { greetings: outG, seeds: outS };
}
