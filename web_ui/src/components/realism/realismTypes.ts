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
  workDays: null,
  likes: [],
  dislikes: [],
  intimateInto: [],
  intimateNotInto: [],
  inventory: {},
  realismVerificationEnabled: false,
  realismVerificationMaxReprocesses: 1,
  realismVerificationStrictness: 3,
  realismNeedsDirectorAuthority: false,
  // AND-gated with the Porch Life global (default on). A new card that
  // writes false silently vetoes Needs even after the engine is turned on.
  needsSimEnabled: true,
  enjoysLowHygiene: false,
  needsSimStrength: 1,
  needsBaselineHunger: 80,
  needsBaselineBladder: 80,
  needsBaselineEnergy: 80,
  needsBaselineSocial: 80,
  needsBaselineFun: 80,
  needsBaselineHygiene: 80,
  needsBaselineComfort: 80,
  needsDecayHunger: 2,
  needsDecayBladder: 3,
  needsDecayEnergy: 3,
  needsDecaySocial: 2,
  needsDecayFun: 2,
  needsDecayHygiene: 1,
  needsDecayComfort: 2,
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

/** Decay-rate description (mirror needs_form_section.dart). */
export function decayDescription(v: number): string {
  if (v === 0) return `Static (0)`;
  if (v <= 2) return `Very Slow (${v})`;
  if (v <= 4) return `Slow (${v})`;
  if (v <= 7) return `Normal (${v})`;
  if (v <= 12) return `Fast (${v})`;
  return `Very Fast (${v})`;
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
