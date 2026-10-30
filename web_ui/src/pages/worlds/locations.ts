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
  /** The climate's own display name (relay-resolved, climate worlds only). */
  climateName?: string | null;
  atmosphere?: string | null;
  gravity?: string | null;
  entryCount?: number;
  enabledEntryCount?: number;
  injectDescription?: boolean;
  /** The starred place chats attached to this world start in; null when
   *  they start in the world itself (resolved by the relay). */
  defaultPlaceId?: string | null;
}

export type LibraryFilter = 'all' | 'modelMade';

/** One place inside a world, as a row in that world's places panel.
 *  depth 1 sits directly inside the world, depth 2 inside a depth-1 place. */
export interface PlaceRowEntry {
  place: TreeWorld;
  depth: number;
}

/** One card in the library: a top-level world and every place inside it,
 *  depth-first. Places never get cards of their own. */
export interface LibraryWorld {
  world: TreeWorld;
  places: PlaceRowEntry[];
}

const idOf = (w: TreeWorld): string => w.id ?? w.name;

/** index by id, so parent lookups match `worldById` (ids only). */
export function indexById(worlds: TreeWorld[]): Map<string, TreeWorld> {
  const byId = new Map<string, TreeWorld>();
  for (const w of worlds) byId.set(idOf(w), w);
  return byId;
}

/** A location is a world whose parent resolves in the library; a dangling
 *  parent id makes a top-level world, not anyone's child (docks with the
 *  Dart planWorldLibrary). */
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
): PlaceRowEntry[] {
  const out: PlaceRowEntry[] = [];
  const seen = new Set<string>([rootId]);
  const walk = (id: string, depth: number) => {
    for (const c of childrenOf(id, worlds, byId)) {
      if (seen.has(idOf(c))) continue;
      seen.add(idOf(c));
      out.push({ place: c, depth });
      walk(idOf(c), depth + 1);
    }
  };
  walk(rootId, 1);
  return out;
}

/** Every place inside [rootId], any depth: what a delete takes with it. */
export function placesInsideCount(
  rootId: string,
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): number {
  return subtreeOf(rootId, worlds, byId).length;
}

/** A bulk delete of [doomed]. A world's delete takes its whole tree, so
 *  only [roots] (doomed rows with no doomed ancestor) are sent; a child
 *  sent after its parent would answer 404 for a row already gone.
 *  [alsoInside] counts the places outside [doomed] that go with them
 *  (desktop bulkDeletePlan twin). */
export function bulkDeletePlan(
  doomed: TreeWorld[],
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): { roots: TreeWorld[]; alsoInside: number } {
  const ids = new Set(doomed.map(idOf));
  const under = new Set<string>();
  for (const d of doomed) {
    for (const p of subtreeOf(idOf(d), worlds, byId)) under.add(idOf(p.place));
  }
  const roots = doomed.filter((d) => !under.has(idOf(d)));
  const inside = new Set<string>();
  for (const r of roots) {
    for (const p of subtreeOf(idOf(r), worlds, byId)) {
      if (!ids.has(idOf(p.place))) inside.add(idOf(p.place));
    }
  }
  return { roots, alsoInside: inside.size };
}

/** Direct children only. */
export function placesUnder(
  rootId: string,
  worlds: TreeWorld[],
  byId: Map<string, TreeWorld>,
): number {
  return childrenOf(rootId, worlds, byId).length;
}

/** The library's cards: every top-level world (a dangling parent counts as
 *  top-level) in library order, each carrying its places. Ring members
 *  (each other's parents: the save path refuses that, a hand-edited
 *  library can still hold it) come last as cards, never vanished. */
export function planWorldLibrary(worlds: TreeWorld[]): LibraryWorld[] {
  const byId = indexById(worlds);
  const cards: LibraryWorld[] = [];
  const placed = new Set<string>();
  for (const w of worlds) {
    if (resolveParent(w, byId) != null) continue;
    const places = subtreeOf(idOf(w), worlds, byId);
    cards.push({ world: w, places });
    placed.add(idOf(w));
    for (const p of places) placed.add(idOf(p.place));
  }
  for (const w of worlds) {
    if (!placed.has(idOf(w))) cards.push({ world: w, places: [] });
  }
  return cards;
}

/** One row in a character's link picker: a top-level world, whether
 *  [refs] link it, and the grey line under it ("3 places inside · chats
 *  start at Stiltwater"), or null when it has no places. */
export interface LinkPickerRow {
  world: TreeWorld;
  linked: boolean;
  inside: string | null;
}

/** Resolve a stored link (id, or an older name) against the library. */
function resolveRef(ref: string, worlds: TreeWorld[], byId: Map<string, TreeWorld>): TreeWorld | undefined {
  return byId.get(ref) ?? worlds.find((w) => w.name === ref);
}

/** Whether [ref] names [world] or a place inside it (an older place link,
 *  which starts chats at that place). Twin of `refLinksWorld`. */
function refLinksWorld(ref: string, world: TreeWorld, worlds: TreeWorld[], byId: Map<string, TreeWorld>): boolean {
  const w = resolveRef(ref, worlds, byId);
  return w != null && idOf(topOf(w, byId)) === idOf(world);
}

/** What a character links: top-level worlds only. A place is reached
 *  through its world, whose starred place starts the chat. An older link
 *  that names a place shows its world as linked, "linked at" that place.
 *  Twin of `linkableWorlds` + `linkStateOf` + `linkPickerInsideLine`. */
export function linkPickerRows(worlds: TreeWorld[], refs: string[]): LinkPickerRow[] {
  const byId = indexById(worlds);
  return planWorldLibrary(worlds).map(({ world }) => {
    const mine = refs.filter((r) => refLinksWorld(r, world, worlds, byId));
    const linkedAt = mine
      .map((r) => resolveRef(r, worlds, byId))
      .find((w) => w != null && idOf(w) !== idOf(world));
    const n = placesUnder(idOf(world), worlds, byId);
    const row = { world, linked: mine.length > 0 };
    if (n === 0) return { ...row, inside: null };
    const count = n === 1 ? '1 place inside' : `${n} places inside`;
    if (linkedAt) return { ...row, inside: `${count} · linked at ${linkedAt.name}` };
    const start = world.defaultPlaceId ? byId.get(world.defaultPlaceId) : undefined;
    return { ...row, inside: start ? `${count} · chats start at ${start.name}` : count };
  });
}

/** [refs] without any that link [world]: unlinking a world also drops an
 *  older link to a place inside it. Twin of `refsWithoutWorld`. */
export function refsWithoutWorld(refs: string[], world: TreeWorld, worlds: TreeWorld[]): string[] {
  const byId = indexById(worlds);
  return refs.filter((r) => !refLinksWorld(r, world, worlds, byId));
}

/** Worlds with places first, each followed by its places; then the rest.
 *  The order attach pickers list in (desktop libraryDisplayOrder twin). */
export function libraryDisplayOrder(worlds: TreeWorld[]): TreeWorld[] {
  const cards = planWorldLibrary(worlds);
  const out: TreeWorld[] = [];
  for (const c of cards) {
    if (c.places.length > 0) out.push(c.world, ...c.places.map((p) => p.place));
  }
  for (const c of cards) if (c.places.length === 0) out.push(c.world);
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
    // Same as Dart's climateAuthorOf: the first world in the run whose
    // weather is not off (the flag defaults to on there and in the relay).
    const author = run.find((w) => w.climateEnabled !== false);
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
