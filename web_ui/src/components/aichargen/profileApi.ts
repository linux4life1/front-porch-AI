// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Profile step and review rewrites on the phone, as the relay
// serves them (/api/chargen/profile…, /continue, /rewrite/…). A create asked
// to pause stops after the profile; the step reads it here, rewrites it
// (streamed over the socket: chargen_profile_progress / _done / _error /
// _stopped), re-reads the facts, and sends Next with the texts and facts as
// the author left them. The same routes take a saved character's id, for a
// phone that went Back from Greetings. The rules are plain functions so they
// are tested without a socket.

import { api } from '../../api/client';

/** The facts the identity pass reads (the relay's IdentityFacts JSON). */
export type Facts = {
  birthday: string;
  occupation: string;
  occupationBrief: string;
  hours: string;
  workDays: number[] | null;
  currentTask: string;
  warmth: string;
  shortTermBond: number;
  trustLevel: number;
  ambitions: string[];
  planLines: string[];
  likes: string[];
  dislikes: string[];
  intimateInto: string[];
  intimateNotInto: string[];
  creatorNotes: string;
};

export const EMPTY_FACTS: Facts = {
  birthday: '',
  occupation: '',
  occupationBrief: '',
  hours: '',
  workDays: null,
  currentTask: '',
  warmth: 'strangers',
  shortTermBond: 0,
  trustLevel: 0,
  ambitions: [],
  planLines: [],
  likes: [],
  dislikes: [],
  intimateInto: [],
  intimateNotInto: [],
  creatorNotes: '',
};

export type ProfileTexts = { description: string; personality: string; scenario: string };

/** What the Profile step shows. `mode` is the wizard mode, or `saved` for a
 *  character already in the library. */
export type ProfileView = ProfileTexts & {
  characterId?: string;
  name: string;
  facts: Facts;
  transcriptQuestions: number;
  transcript: string;
  userScenario: boolean;
  mode: string;
  nsfw: boolean;
  age: string;
  /** The model call running on it: `rewrite`, `facts`, `complete`, or null. */
  writing: string | null;
};

const str = (v: unknown) => (typeof v === 'string' ? v : '');
const strs = (v: unknown) => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
const num = (v: unknown) => (typeof v === 'number' ? v : 0);

/** A relay facts object read defensively. */
export function factsOf(raw: unknown): Facts {
  const j = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  return {
    birthday: str(j.birthday),
    occupation: str(j.occupation),
    occupationBrief: str(j.occupationBrief),
    hours: str(j.hours),
    workDays: Array.isArray(j.workDays) ? j.workDays.filter((d): d is number => typeof d === 'number') : null,
    currentTask: str(j.currentTask),
    warmth: str(j.warmth) || 'strangers',
    shortTermBond: num(j.shortTermBond),
    trustLevel: num(j.trustLevel),
    ambitions: strs(j.ambitions),
    planLines: strs(j.planLines),
    likes: strs(j.likes),
    dislikes: strs(j.dislikes),
    intimateInto: strs(j.intimateInto),
    intimateNotInto: strs(j.intimateNotInto),
    creatorNotes: str(j.creatorNotes),
  };
}

/** A `chargen_profile` event or a GET answer as the step's view. */
export function viewOf(raw: unknown): ProfileView | null {
  if (!raw || typeof raw !== 'object') return null;
  const j = raw as Record<string, unknown>;
  return {
    characterId: typeof j.characterId === 'string' ? j.characterId : undefined,
    name: str(j.name),
    description: str(j.description),
    personality: str(j.personality),
    scenario: str(j.scenario),
    facts: factsOf(j.facts),
    transcriptQuestions: num(j.transcriptQuestions),
    transcript: str(j.transcript),
    userScenario: j.userScenario === true,
    mode: str(j.mode) || 'quick',
    nsfw: j.nsfw === true,
    age: str(j.age),
    writing: typeof j.writing === 'string' ? j.writing : null,
  };
}

const enc = encodeURIComponent;
const idOf = (characterId?: string) => (characterId ? { characterId } : {});

/** The run waiting for Next (`creating` while Phase A still runs). */
export async function loadPending(): Promise<{ pending: ProfileView | null; creating: boolean }> {
  const r = await api.get<{ pending: unknown; creating?: boolean }>('/api/chargen/profile');
  return { pending: viewOf(r.pending), creating: r.creating === true };
}

/** A saved character's profile, for the step after Back from Greetings. */
export async function loadSaved(characterId: string): Promise<ProfileView | null> {
  const r = await api.get<{ pending: unknown }>(`/api/chargen/profile?characterId=${enc(characterId)}`);
  return viewOf(r.pending);
}

export const startProfileRewrite = (texts: ProfileTexts, direction: string, characterId?: string) =>
  api.post<{ status: string }>('/api/chargen/profile/rewrite', { ...texts, direction, ...idOf(characterId) });

export const stopProfile = (characterId?: string) =>
  api.post<{ stopped: boolean }>('/api/chargen/profile/stop', idOf(characterId));

export const startFactsReread = (texts: ProfileTexts, characterId?: string) =>
  api.post<{ status: string }>('/api/chargen/profile/facts', { ...texts, ...idOf(characterId) });

/** Next: the rest of the card for the pending run (`started`), or the
 *  texts and facts saved to a saved character (`saved`). */
export const continueProfile = (texts: ProfileTexts, facts: Facts, characterId?: string) =>
  api.post<{ status: string; phase?: string }>('/api/chargen/continue', { ...texts, facts, ...idOf(characterId) });

/** What a `chargen_profile_progress` event shows: which box is being written
 *  and each box's text so far. `field` is `none` before the first key. */
export type ProfileProgress = { field: string; description: string; personality: string; scenario: string };

export function progressOf(e: { field?: string; description?: string; personality?: string; scenario?: string }): ProfileProgress {
  return {
    field: e.field ?? 'none',
    description: e.description ?? '',
    personality: e.personality ?? '',
    scenario: e.scenario ?? '',
  };
}

/** How a box reads while the profile is rewritten. Description is written
 *  first; Personality waits for it; Scenario is kept as it is. In Automated
 *  mode the description is the author's own and stays. */
export type BoxState = 'writing' | 'waiting' | 'kept' | 'built' | null;

export function boxStates(p: ProfileProgress | null, mode: string): Record<keyof ProfileTexts, BoxState> {
  if (!p) return { description: null, personality: null, scenario: null };
  const automated = mode === 'automated';
  const personalityStarted = p.field === 'personality' || p.field === 'scenario';
  return {
    description: automated ? 'built' : personalityStarted ? null : 'writing',
    personality: personalityStarted ? 'writing' : 'waiting',
    scenario: 'kept',
  };
}

/** The read-only opening stance: `Strangers · bond 0 · trust 0`. */
export function stanceOf(f: Facts): string {
  const w = f.warmth || 'strangers';
  return `${w.charAt(0).toUpperCase()}${w.slice(1)} · bond ${f.shortTermBond} · trust ${f.trustLevel}`;
}

/** The birthday row's label: the age from Setup when there is one. */
export function birthdayLabel(age: string, phone: boolean): string {
  const n = age.match(/\d+/)?.[0];
  if (!n) return 'BIRTHDAY';
  return phone ? `BIRTHDAY · AGE ${n}` : `BIRTHDAY · AGE ${n} FROM SETUP`;
}

/** Rows for a textarea that grows with its text (no resize handle). */
export function rowsFor(text: string, min = 1, max = 8): number {
  const lines = text.split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.length / 38)), 0);
  return Math.min(max, Math.max(min, lines));
}

// ── The review rewrites (the foot of the phone's Greetings step) ──────────

export type LoreRow = { name: string; content: string; handEdited: boolean };
export type Review = { mesExample: string; lorebook: LoreRow[]; writing: string | null; sex: string };

export function loreRowsOf(raw: unknown): LoreRow[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((r): r is Record<string, unknown> => !!r && typeof r === 'object')
    .map((r) => ({ name: str(r.name), content: str(r.content), handEdited: r.handEdited === true }));
}

export async function loadReview(characterId: string): Promise<Review> {
  const r = await api.get<Record<string, unknown>>(`/api/chargen/review?characterId=${enc(characterId)}`);
  return {
    mesExample: str(r.mesExample),
    lorebook: loreRowsOf(r.lorebook),
    writing: typeof r.writing === 'string' ? r.writing : null,
    sex: str(r.sex),
  };
}

export const startReviewRewrite = (characterId: string, field: 'mesExample' | 'lorebook', direction: string) =>
  api.post<{ status: string }>(field === 'mesExample' ? '/api/chargen/rewrite/dialogue' : '/api/chargen/rewrite/lorebook', {
    characterId,
    direction,
  });

export const stopReviewRewrite = (characterId: string) =>
  api.post<{ stopped: boolean }>('/api/chargen/rewrite/stop', { characterId });

export const saveExampleDialogue = (characterId: string, text: string) =>
  api.post(`/api/characters/${enc(characterId)}`, { mesExample: text });

/** "How she answers, learned from the interview": the pronoun from the
 *  Sex field, "they" when unknown. */
export function dialogueSubtitle(sex: string): string {
  const s = sex.trim().toLowerCase();
  if (/^(f|female|woman|girl|she)\b/.test(s)) return 'How she answers, learned from the interview';
  if (/^(m|male|man|boy|he)\b/.test(s)) return 'How he answers, learned from the interview';
  return 'How they answer, learned from the interview';
}

// ── The profile-changed hint on the Greetings step ────────────────────────

export const rewriteAllGreetings = (characterId: string) =>
  api.post<{ status: string; count: number }>('/api/chargen/greeting/rewrite-all', { characterId });

export const keepGreetings = (characterId: string) =>
  api.post<{ ok: boolean }>('/api/chargen/greeting/keep-profile', { characterId });
