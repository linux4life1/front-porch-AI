// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Cast screen's edits and the small words on a dossier. Each edit returns
// the slices of the project it changed, ready to hand to `save`, the way the
// desktop's CastSection mutates the project and saves it. Pure.

import type { StoryCastMember, StoryProject, StoryRelationship } from '../../../storyTypes';

/** The five fields of the Add / Edit dialog. */
export interface CastFields {
  name: string;
  role: string;
  description: string;
  desire: string;
  flaw: string;
}

export const castFields = (m: StoryCastMember | null): CastFields => ({
  name: m?.name ?? '',
  role: m?.role ?? '',
  description: m?.description ?? '',
  desire: m?.desire ?? '',
  flaw: m?.flaw ?? '',
});

/** Add a character (index null) or change one's five fields; everything else on the dossier stays. */
export function saveMember(p: StoryProject, index: number | null, f: CastFields): Pick<StoryProject, 'cast'> {
  const fields = {
    name: f.name.trim(), role: f.role.trim(), description: f.description.trim(), desire: f.desire.trim(), flaw: f.flaw.trim(),
  };
  if (index === null) return { cast: [...p.cast, { ...fields, details: {} }] };
  return { cast: p.cast.map((m, i) => (i === index ? { ...m, ...fields } : m)) };
}

/** Take someone out of the cast and every relationship they are in. */
export function removeMember(p: StoryProject, index: number): Pick<StoryProject, 'cast' | 'relationships'> {
  const name = p.cast[index]?.name;
  const relationships: StoryRelationship[] = (p.relationships ?? []).filter((r) => r.from !== name && r.to !== name);
  return { cast: p.cast.filter((_, i) => i !== index), relationships };
}

/** The voice a character reads aloud with; '' goes back to the default narrator. */
export function setVoice(p: StoryProject, index: number, voiceId: string): Pick<StoryProject, 'cast'> {
  return { cast: p.cast.map((m, i) => (i === index ? { ...m, voice_model: voiceId || undefined } : m)) };
}

/** "Protagonist · wants freedom · flaw: pride": the line under a name. */
export function memberMeta(m: StoryCastMember): string {
  return [m.role, m.desire ? `wants ${m.desire}` : '', m.flaw ? `flaw: ${m.flaw}` : ''].filter(Boolean).join(' · ');
}

export const shortText = (s: string): string => (s.length > 40 ? `${s.slice(0, 40)}…` : s);

/** The interview as the card quotes it: 420 characters, then an ellipsis. */
export const interviewExcerpt = (s: string): string => (s.length > 420 ? `${s.slice(0, 420)}…` : s);

export const firstName = (name: string): string => name.split(' ')[0];
