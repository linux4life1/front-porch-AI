// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Greetings step (#370) on the phone. Rewrites, adds and deletes
// go to the relay (POST /api/chargen/greeting…), which runs the same
// regenerateGreeting the desktop does and streams over the socket
// (chargen_greeting_progress / _done / _error / _stopped). Typed edits save
// through the normal character update (POST /api/characters/:id). The merge
// rules are plain functions so they are tested without a socket.

import { api } from '../../api/client';

/** Most alternates a card gets here (the relay's kMaxAlternateGreetings). */
export const MAX_ALTERNATES = 5;

/** What the step holds. `seeds` are the alternates' starting states, opaque
 *  here and kept aligned, so saving the alternates never drops one. */
export type Greetings = { first: string; alts: string[]; seeds: unknown[] };

/** The greeting being written: 0 is the first message, 1 and up the
 *  alternates, one past the last while Add another writes. */
export type Writing = { index: number; text: string };

type Detail = {
  firstMessage?: string;
  alternateGreetings?: string[];
  realism?: { greetingSeeds?: unknown[] } | null;
};

const enc = encodeURIComponent;

export function alignSeeds(seeds: unknown[], n: number): unknown[] {
  if (seeds.length >= n) return seeds.slice(0, n);
  return [...seeds, ...Array<unknown>(n - seeds.length).fill(null)];
}

export async function loadGreetings(id: string): Promise<Greetings> {
  const d = await api.get<Detail>(`/api/characters/${enc(id)}/detail`);
  const alts = d.alternateGreetings ?? [];
  return {
    first: d.firstMessage ?? '',
    alts,
    seeds: alignSeeds(d.realism?.greetingSeeds ?? [], alts.length),
  };
}

export const saveFirst = (id: string, text: string) =>
  api.post(`/api/characters/${enc(id)}`, { firstMessage: text });

export const saveAlternates = (id: string, g: Greetings) =>
  api.post(`/api/characters/${enc(id)}`, {
    alternateGreetings: g.alts,
    greetingSeeds: alignSeeds(g.seeds, g.alts.length),
  });

export const startRewrite = (id: string, index: number, direction: string) =>
  api.post<{ status: string; index: number }>('/api/chargen/greeting', {
    characterId: id,
    index,
    direction,
  });

export const startAdd = (id: string) =>
  api.post<{ status: string; index: number }>('/api/chargen/greeting/add', { characterId: id });

export const deleteAlternate = (id: string, index: number) =>
  api.post<{ firstMessage: string; alternateGreetings: string[] }>(
    '/api/chargen/greeting/delete',
    { characterId: id, index },
  );

export const stopWriting = (id: string) =>
  api.post<{ stopped: boolean }>('/api/chargen/greeting/stop', { characterId: id });

export const writingStatus = (id: string) =>
  api.get<{ writing: number | null }>(`/api/chargen/greeting/status?characterId=${enc(id)}`);

/** A finished greeting into what the step holds. Only that slot changes, so
 *  text typed into the others meanwhile stays (and is saved right after). */
export function applyWritten(g: Greetings, index: number, text: string): Greetings {
  if (index === 0) return { ...g, first: text };
  const alts = [...g.alts];
  const seeds = alignSeeds(g.seeds, alts.length);
  if (index <= alts.length) {
    alts[index - 1] = text;
  } else {
    alts.push(text);
    seeds.push(null);
  }
  return { first: g.first, alts, seeds };
}

/** Alternate [index] (1 and up) gone, its starting state with it. */
export function withoutAlternate(g: Greetings, index: number): Greetings {
  const keep = (_: unknown, i: number) => i !== index - 1;
  return {
    first: g.first,
    alts: g.alts.filter(keep),
    seeds: alignSeeds(g.seeds, g.alts.length).filter(keep),
  };
}
