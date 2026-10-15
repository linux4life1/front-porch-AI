// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Interview card's rows on the phone (docs/design/creator-interview-
// questions.md). A row is a standard question (by key, worded for the voice
// by the relay), an edited one (its text kept as written whatever the voice
// does later) or a custom one (no key). The two conditional rows keep their
// condition through an edit and cannot be removed. The wording lives in
// lib/services/chargen/interview_questions.dart; the relay renders it for
// the voice (GET /api/chargen/interview), so the web only shows it.

import { api } from '../../api/client';

export type InterviewCondition = 'relationship' | 'nsfw';

/** One row of the card. `text` is null for a standard row not yet edited. */
export type InterviewRow = {
  id: string;
  key: string | null;
  text: string | null;
  condition: InterviewCondition | null;
};

/** A standard question as the relay words it for the current voice. */
export type StandardQuestion = { key: string; condition: InterviewCondition | null; text: string };

export type StandardSet = {
  pronouns: { subject: string; possessive: string };
  rows: StandardQuestion[];
};

export const INTERVIEW_CAP = 12;

/** The row as the create body carries it (`interviewQuestions`). */
export type InterviewPayloadRow = Omit<InterviewRow, 'id'>;

let lastId = 0;

/** The untouched standard set. Ids follow the key, so a re-fetch in a new
 *  voice keeps every row's identity. */
export const rowsFrom = (standard: StandardQuestion[]): InterviewRow[] =>
  standard.map((q) => ({ id: `std-${q.key}`, key: q.key, text: null, condition: q.condition }));

export const isEdited = (row: InterviewRow) => row.key !== null && row.text !== null;

export const editRow = (rows: InterviewRow[], id: string, text: string): InterviewRow[] =>
  rows.map((r) => (r.id === id ? { ...r, text } : r));

/** A conditional row cannot be removed: the list comes back unchanged. */
export function removeRow(rows: InterviewRow[], id: string): InterviewRow[] {
  const row = rows.find((r) => r.id === id);
  if (!row || row.condition) return rows;
  return rows.filter((r) => r.id !== id);
}

/** A new custom row at the end; at the cap the list comes back unchanged. */
export function addRow(rows: InterviewRow[], cap = INTERVIEW_CAP): InterviewRow[] {
  if (rows.length >= cap) return rows;
  lastId += 1;
  return [...rows, { id: `new-${lastId}`, key: null, text: '', condition: null }];
}

export function moveRow(rows: InterviewRow[], from: number, to: number): InterviewRow[] {
  if (from === to || from < 0 || to < 0 || from >= rows.length || to >= rows.length) return rows;
  const next = [...rows];
  const [row] = next.splice(from, 1);
  next.splice(to, 0, row);
  return next;
}

/** What the row's box shows: its own text, else the standard wording. */
export const rowText = (row: InterviewRow, standardTextByKey: Record<string, string>): string =>
  row.text ?? (row.key ? (standardTextByKey[row.key] ?? '') : '');

export const toPayload = (rows: InterviewRow[]): InterviewPayloadRow[] =>
  rows.map(({ key, text, condition }) => ({ key, text, condition }));

/** The untouched standard set: every standard row, in order, none edited.
 *  The form keeps null for it, so the create body leaves the field out. */
export const isStandardList = (rows: InterviewRow[], standard: StandardQuestion[]): boolean =>
  rows.length === standard.length && rows.every((r, i) => r.key === standard[i].key && r.text === null);

const str = (v: unknown) => (typeof v === 'string' ? v : '');
const conditionOf = (v: unknown): InterviewCondition | null =>
  v === 'relationship' || v === 'nsfw' ? v : null;

/** The relay's answer read defensively. An answer with no rows is a
 *  failure, not an empty interview. */
export function standardSetOf(raw: unknown): StandardSet {
  const j = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const p = (j.pronouns && typeof j.pronouns === 'object' ? j.pronouns : {}) as Record<string, unknown>;
  const rows = (Array.isArray(j.rows) ? j.rows : [])
    .filter((r): r is Record<string, unknown> => !!r && typeof r === 'object' && typeof r.key === 'string')
    .map((r) => ({ key: r.key as string, condition: conditionOf(r.condition), text: str(r.text) }));
  if (rows.length === 0) throw new Error('the relay answered no interview questions');
  return { pronouns: { subject: str(p.subject) || 'they', possessive: str(p.possessive) || 'their' }, rows };
}

/** The standard questions worded for this voice and Sex. */
export async function loadStandard(perspective: string, tense: string, sex: string): Promise<StandardSet> {
  const q = new URLSearchParams({ perspective, tense, sex }).toString();
  return standardSetOf(await api.get<unknown>(`/api/chargen/interview?${q}`));
}

export const voicePill = (perspective: 'first' | 'third', tense: 'present' | 'past') =>
  `Answered in ${perspective} person, ${tense}`;

/** The desktop caption beside the pill; in the third person it names whose
 *  words are quoted (`Their … they` when the Sex field says nothing). */
export function followsCaption(perspective: 'first' | 'third', pronouns: StandardSet['pronouns']): string {
  if (perspective === 'first') return 'Follows Narrative voice above.';
  const { subject, possessive } = pronouns;
  const verb = subject === 'they' ? 'speak' : 'speaks';
  return `Follows Narrative voice above. ${possessive.charAt(0).toUpperCase()}${possessive.slice(1)} own words are quoted when ${subject} ${verb}.`;
}

export const countCaption = (n: number, phone: boolean, none = false) => {
  if (none) {
    return phone
      ? `${n} of ${INTERVIEW_CAP} · no interview: the profile comes from your settings`
      : `${n} of ${INTERVIEW_CAP} · no interview: the profile comes straight from your settings`;
  }
  return phone
    ? `${n} of ${INTERVIEW_CAP} · none means no interview`
    : `${n} of ${INTERVIEW_CAP} · remove them all and the profile comes straight from your settings, no interview`;
};

/** No unconditional row with text is left, so the run asks nothing: the
 *  two conditional rows cannot be removed, and the engine drops them on
 *  their own. */
export const asksNothing = (rows: InterviewRow[], textByKey: Record<string, string>) =>
  !rows.some((r) => !r.condition && rowText(r, textByKey).trim() !== '');
