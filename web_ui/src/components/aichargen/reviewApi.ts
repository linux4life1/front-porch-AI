// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's data (PR 8d): the saved card's text fields, tags, seeds
// and full lorebook entries from /detail, and the one save verb the step
// needs. The review rewrites and the example dialogue stay in profileApi.ts
// (they were already the Greetings step's).

import { api } from '../../api/client';
import type { LoreEntry } from '../LoreEntriesEditor';
import type { GreetingSeed } from '../realism/realismTypes';
import { alignSeeds } from './greetingsApi';

export type ReviewDetail = {
  name: string;
  description: string;
  personality: string;
  scenario: string;
  firstMessage: string;
  systemPrompt: string;
  alternateGreetings: string[];
  seeds: (GreetingSeed | null)[];
  tags: string[];
  lorebook: LoreEntry[];
};

const str = (v: unknown) => (typeof v === 'string' ? v : '');
const enc = encodeURIComponent;

/** A saved card as the Review step shows it. The lorebook keeps every field
 *  the card carries (the entry editor round-trips the ones it does not edit). */
export async function loadReviewDetail(id: string): Promise<ReviewDetail> {
  const d = await api.get<Record<string, any>>(`/api/characters/${enc(id)}/detail`);
  const alts = Array.isArray(d.alternateGreetings) ? d.alternateGreetings.map(str) : [];
  const rawSeeds = d.realism?.greetingSeeds;
  const seeds = Array.isArray(rawSeeds) ? (rawSeeds as (GreetingSeed | null)[]) : [];
  const rawLore = Array.isArray(d.lorebook?.entries) ? d.lorebook.entries : [];
  const lorebook = rawLore
    .filter((e: unknown): e is Record<string, unknown> => !!e && typeof e === 'object')
    .map(
      (e: Record<string, unknown>) =>
        ({
          name: '',
          key: '',
          content: '',
          enabled: true,
          constant: false,
          stickyDepth: 1,
          ...e,
        }) as LoreEntry,
    );
  return {
    name: str(d.name),
    description: str(d.description),
    personality: str(d.personality),
    scenario: str(d.scenario),
    firstMessage: str(d.firstMessage),
    systemPrompt: str(d.systemPrompt),
    alternateGreetings: alts,
    seeds: alignSeeds(seeds, alts.length) as (GreetingSeed | null)[],
    tags: Array.isArray(d.tags) ? d.tags.map(str) : [],
    lorebook,
  };
}

/** One partial update: only the keys sent are touched by the host. */
export const saveFields = (id: string, fields: Record<string, unknown>) =>
  api.post(`/api/characters/${enc(id)}`, fields);
