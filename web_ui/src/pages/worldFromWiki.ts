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

function stringList(raw: unknown): string[] {
  if (Array.isArray(raw)) {
    return raw.map((e) => String(e).trim()).filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim()) {
    return raw.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return [];
}
