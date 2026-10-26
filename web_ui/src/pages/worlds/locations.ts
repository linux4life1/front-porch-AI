// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure library-plumbing for the locations web twin (slice 4). Grouping,
// counts, and the setting-prose injection mirror the Dart law in
// lib/services/world_chain.dart and prompt_injection/world_injection.dart
// — these are presentation-time helpers only; legality of a move is ALWAYS
// re-decided server-side (relay save + parent-candidates), never here.

export interface TreeWorld {
  id?: string;
  name: string;
  description?: string;
  parentWorldId?: string | null;
  climateEnabled?: boolean;
  isModelMade?: boolean;
  biomeId?: string | null;
  atmosphere?: string | null;
  gravity?: string | null;
  entryCount?: number;
  enabledEntryCount?: number;
  injectDescription?: boolean;
}

export type LibraryFilter = 'all' | 'rootsOnly' | 'modelMade';

export interface LibrarySection {
  root: TreeWorld;
  children: TreeWorld[];
}

export interface LibraryPlan {
  sections: LibrarySection[];
  flat: TreeWorld[];
}

const idOf = (w: TreeWorld): string => w.id ?? w.name;

/** index by id, so parent lookups match `worldById` (ids only). */
export function indexById(worlds: TreeWorld[]): Map<string, TreeWorld> {
  const byId = new Map<string, TreeWorld>();
  for (const w of worlds) byId.set(idOf(w), w);
  return byId;
}

/** A location is a world whose parent resolves in the library; a dangling
 *  parent id is flat cargo, not anyone's child (docks with the Dart
 *  planWorldLibrary). */
export function resolveParent(
  w: TreeWorld,
  byId: Map<string, TreeWorld>,
): TreeWorld | null {
  const p = w.parentWorldId;
  if (p == null || p === '') return null;
  return byId.get(p) ?? null;
}

function childrenOf(
  rootId: string,
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): TreeWorld[] {
  return worlds
    .filter((w) => {
      const p = resolveParent(w, byId);
      return p != null && idOf(p) === rootId;
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

/** Depth-first: every child followed immediately by its own children. */
function subtreeOf(
  rootId: string,
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): TreeWorld[] {
  const out: TreeWorld[] = [];
  const walk = (id: string) => {
    for (const c of childrenOf(id, worlds, byId)) {
      out.push(c);
      walk(idOf(c));
    }
  };
  walk(rootId);
  return out;
}

/** Direct children only — the chip's number, per mockup p1 (deeper counts
 *  ride each child's own chip). */
export function placesUnder(
  rootId: string,
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): number {
  return childrenOf(rootId, worlds, byId).length;
}

export function planWorldLibrary(
  worlds: TreeWorld[],
  filter: LibraryFilter,
): LibraryPlan {
  const byId = indexById(worlds);
  if (filter === 'modelMade') {
    return { sections: [], flat: worlds.filter((w) => w.isModelMade === true) };
  }
  const sections: LibrarySection[] = [];
  const flat: TreeWorld[] = [];
  for (const w of worlds) {
    if (resolveParent(w, byId) != null) continue; // children ride sections
    const children =
      filter === 'rootsOnly' ? [] : subtreeOf(idOf(w), worlds, byId);
    if (childrenOf(idOf(w), worlds, byId).length > 0) {
      sections.push({ root: w, children });
    } else {
      flat.push(w);
    }
  }
  const placed = new Set<string>();
  for (const s of sections) {
    placed.add(idOf(s.root));
    // rootsOnly hides descendants but they are still FILED under their
    // section — the ring sweep below must not drag them into flat.
    for (const d of subtreeOf(idOf(s.root), worlds, byId)) placed.add(idOf(d));
  }
  // Unfiled cargo (rings, direct-DB cycles): flat, never vanished.
  for (const w of worlds) {
    if (resolveParent(w, byId) != null && !placed.has(idOf(w))) flat.push(w);
  }
  return { sections, flat };
}

/** Roots first with subtrees beneath; dangling parents last — the order
 *  attach pickers list in (desktop libraryDisplayOrder twin). */
export function libraryDisplayOrder(worlds: TreeWorld[]): TreeWorld[] {
  const plan = planWorldLibrary(worlds, 'all');
  const out: TreeWorld[] = [];
  for (const s of plan.sections) out.push(s.root, ...s.children);
  out.push(...plan.flat);
  return out;
}

// ── Setting prose (twin of world_injection.dart) ─────────────────────────

export const WORLD_INJECTION_MAX_CHARS = 600;

const ATMOSPHERE_LINES: Record<string, string> = {
  thin:
    'The air is thin — unassisted breathing is labored, and real exertion ' +
    'needs masks or acclimatization.',
  unbreathable:
    'The air is unbreathable — no one steps outside unsealed; the airlock ' +
    'is a ritual, not a door.',
  hostile:
    'The air itself is hostile — exposure damages skin and equipment, and ' +
    'time outside is rationed and urgent.',
};

const GRAVITY_LINES: Record<string, string> = {
  low:
    'Gravity is low — bounding strides come easy, and dropped things fall ' +
    'lazily.',
  high: 'Gravity is high — every limb is heavy, and effort taxes twice as fast.',
  micro:
    'There is almost no gravity — nothing stays down; people float, tether, ' +
    'and drift.',
};

function traitLine(w: TreeWorld): string {
  // Mirrors atmosphereLine/gravityLine: defaults are silent, and the
  // strings are what the model READS — kept byte-identical to the Dart
  // builder so this preview is the same sentence the prompt carries.
  const parts: string[] = [];
  if (w.atmosphere && ATMOSPHERE_LINES[w.atmosphere]) {
    parts.push(ATMOSPHERE_LINES[w.atmosphere]);
  }
  if (w.gravity && GRAVITY_LINES[w.gravity]) {
    parts.push(GRAVITY_LINES[w.gravity]);
  }
  return parts.join(' ');
}

/**
 * The worlds that speak trait lines: the climate author of each
 * parent-linked run (twin of `_traitAuthors` in world_injection.dart). A
 * Setting chain is one run, so a place that owns a climate also owns its
 * air and gravity and the worlds above it add prose only
 * (locations-within-worlds.md §3 rule 2). A world that says
 * `climateEnabled: true` is preferred as the author over one that does not
 * say (the relay always sends the flag; a hand-built row may not).
 */
function traitAuthors(chain: TreeWorld[]): Set<TreeWorld> {
  const authors = new Set<TreeWorld>();
  let start = 0;
  for (let i = 0; i < chain.length; i++) {
    const parent = chain[i].parentWorldId;
    const next = chain[i + 1];
    if (next !== undefined && parent != null && parent !== '' && parent === idOf(next)) {
      continue;
    }
    const run = chain.slice(start, i + 1);
    start = i + 1;
    // A run whose top has weather off has no author (climateAuthorOf).
    if (run[run.length - 1].climateEnabled === false) continue;
    const author =
      run.find((w) => w.climateEnabled === true) ??
      run.find((w) => w.climateEnabled !== false);
    if (author) authors.add(author);
  }
  return authors;
}

/**
 * Leaf-first budget injection: the Setting's own prose wins the budget,
 * parents fill what is left (same order, header rule, 40-char floor and
 * trait-protection as the Dart builder). `chain` must arrive leaf-first.
 *
 * Like the Dart original: `injectDescription: false` blanks the
 * DESCRIPTION only — behavioral trait lines ride on, because the author
 * picked them explicitly. Trait lines come from the chain's climate author
 * only (see traitAuthors).
 */
export function buildWorldInjection(chain: TreeWorld[]): string {
  const parts: string[] = [];
  let used = 0;
  // A top-level world with weather off silences every place inside it.
  const root = chain[chain.length - 1];
  const traitsLive = root === undefined || root.climateEnabled !== false;
  const authors = traitAuthors(chain);
  for (const w of chain) {
    const desc = w.injectDescription === false ? '' : (w.description ?? '').trim();
    const traits = traitsLive && authors.has(w) ? traitLine(w) : '';
    if (!desc && !traits) continue;
    const header = w.name.trim() === '' ? 'This place' : w.name.trim();
    const body = [desc, traits].filter(Boolean).join(' ');
    const block = `${header}: ${body}`;
    if (used + block.length > WORLD_INJECTION_MAX_CHARS) {
      const remain = WORLD_INJECTION_MAX_CHARS - used;
      if (remain < 40) break;
      const descBudget = remain - traits.length - header.length - 2;
      if (traits && descBudget > 0 && desc) {
        const cut =
          desc.length > descBudget ? desc.slice(0, descBudget).trimEnd() : desc;
        parts.push(`${header}: ${cut} ${traits}`);
      } else if (traits && remain >= traits.length + header.length) {
        parts.push(`${header}: ${traits}`);
      } else {
        parts.push(block.slice(0, remain).trimEnd());
      }
      break;
    }
    parts.push(block);
    used += block.length + 1;
  }
  if (parts.length === 0) return '';
  return `Setting — where you are:\n${parts.join('\n')}`;
}

const PREFIX = 'Setting — where you are:\n';

/** The counter under the preview: what the engine counted (blocks plus a
 *  separator per block), not string eyeballs — one budget, one number. */
export function injectionUsedChars(text: string): number {
  if (!text) return 0;
  const body = text.startsWith(PREFIX) ? text.slice(PREFIX.length) : text;
  return body.length + 1;
}

/** The top-level world above [w] (or [w] itself for a root); ring-safe. */
export function topOf(w: TreeWorld, byId: Map<string, TreeWorld>): TreeWorld {
  let top = w;
  let cursor: TreeWorld | null = w;
  const seen = new Set<string>();
  while (cursor != null) {
    const key = cursor.id ?? cursor.name;
    if (seen.has(key)) break;
    seen.add(key);
    top = cursor;
    cursor = resolveParent(cursor, byId);
  }
  return top;
}
