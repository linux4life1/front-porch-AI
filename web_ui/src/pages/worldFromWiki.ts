// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World-from-wiki review shelf: proposed cards, not a wiki table of contents.

export const WORLD_FROM_WIKI_STEPS = ['Book', 'Review', 'Write', 'Preview'];

export const WORLD_FROM_WIKI_TOOLS_COPY =
  'Pick a tool-calling model (Qwen 27B, etc.). This wizard needs tools — it will not dump the wiki into one prompt.';

export type WorldCraftRole = 'era' | 'hub' | 'leaf' | 'crown';

export type ProposedWorldCard = {
  name: string;
  keys: string[];
  role: WorldCraftRole;
  sourceTitles: string[];
  group?: string;
};

export function parseProposedCards(raw: unknown): ProposedWorldCard[] {
  if (!Array.isArray(raw)) return [];
  const out: ProposedWorldCard[] = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') continue;
    const row = item as Record<string, unknown>;
    const name = String(row.name ?? '').trim();
    const role = String(row.role ?? '').trim() as WorldCraftRole;
    if (!name || !['era', 'hub', 'leaf', 'crown'].includes(role)) continue;
    const sourceTitles = stringList(row.sourceTitles ?? row.source_titles).slice(0, 3);
    if (!sourceTitles.length) continue;
    out.push({
      name,
      keys: stringList(row.keys),
      role,
      sourceTitles,
      group: String(row.group ?? '').trim() || undefined,
    });
  }
  return out;
}

/** Review is a signed shelf. Never select-all on the wiki title list. */
export function signedCards(
  proposed: ProposedWorldCard[],
  signed: ReadonlySet<number>,
): ProposedWorldCard[] {
  return proposed.filter((_, i) => signed.has(i));
}

const REVIEW_STEP = 1;
const WRITE_STEP = 2;
const PREVIEW_STEP = 3;

export function canOpenWorldFromWikiReview(opts: {
  lorebooksOn: boolean;
  proposedCount: number;
}): boolean {
  return opts.lorebooksOn && opts.proposedCount > 0;
}

export function canOpenWorldFromWikiWrite(opts: {
  lorebooksOn: boolean;
  signedCount: number;
}): boolean {
  return opts.lorebooksOn && opts.signedCount > 0;
}

export function canOpenWorldFromWikiPreview(opts: {
  lorebooksOn: boolean;
  aborted: boolean;
  entryCount: number;
}): boolean {
  if (opts.aborted) return false;
  if (!opts.lorebooksOn) return true;
  return opts.entryCount > 0;
}

/** Linear safety: Review needs a scout, Write needs a signed shelf, Preview needs a write. */
export function jumpWorldFromWikiStep(
  next: number,
  current: number,
  opts: {
    lorebooksOn: boolean;
    aborted: boolean;
    entryCount: number;
    proposedCount?: number;
    signedCount?: number;
    previewStep?: number;
  },
): number {
  const proposedCount = opts.proposedCount ?? 0;
  const signedCount = opts.signedCount ?? 0;
  const preview = opts.previewStep ?? PREVIEW_STEP;
  if (
    next === REVIEW_STEP &&
    !canOpenWorldFromWikiReview({
      lorebooksOn: opts.lorebooksOn,
      proposedCount,
    })
  ) {
    return current;
  }
  if (
    next === WRITE_STEP &&
    !canOpenWorldFromWikiWrite({
      lorebooksOn: opts.lorebooksOn,
      signedCount,
    })
  ) {
    return current;
  }
  if (next === preview && !canOpenWorldFromWikiPreview(opts)) return current;
  return next;
}

function stringList(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.map((e) => String(e).trim()).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim()) {
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return [];
}
