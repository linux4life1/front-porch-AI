// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryCastMember, StoryRelationship } from '../../../storyTypes';
import { studioStory } from '../storyFixture';
import {
  castFields, firstName, interviewExcerpt, memberMeta, removeMember, saveMember, setVoice, shortText,
} from './castEdits';

const member = (name: string, patch: Partial<StoryCastMember> = {}): StoryCastMember => ({
  name, role: '', description: '', details: {}, ...patch,
});

const rel = (from: string, to: string): StoryRelationship => ({ from, to, feeling: 'Fond', note: '', subtext: '', trust: 5, history: [] });

const story = () => studioStory({
  cast: [member('Mara', { role: 'Protagonist', interview: 'Tired, mostly.', voice_model: 'amy' }), member('Joss'), member('Teodor')],
  relationships: [rel('Mara', 'Joss'), rel('Joss', 'Mara'), rel('Joss', 'Teodor')],
});

describe('Cast edits (sketch R)', () => {
  it('adds a character with trimmed fields and an empty dossier', () => {
    const { cast } = saveMember(story(), null, { name: '  Wren ', role: 'Mentor', description: 'Keeps the light.', desire: ' to be waited for ', flaw: '' });
    expect(cast).toHaveLength(4);
    expect(cast[3]).toEqual({ name: 'Wren', role: 'Mentor', description: 'Keeps the light.', desire: 'to be waited for', flaw: '', details: {} });
  });

  it('edits the five fields and leaves interview, voice and secret alone', () => {
    const p = story();
    p.cast[0].details = { secret: 'kept the ledger' };
    const { cast } = saveMember(p, 0, { name: 'Mara', role: 'Lead', description: 'Tired.', desire: 'freedom', flaw: 'pride' });
    expect(cast[0]).toMatchObject({ role: 'Lead', desire: 'freedom', flaw: 'pride', interview: 'Tired, mostly.', voice_model: 'amy', details: { secret: 'kept the ledger' } });
    expect(cast[1].name).toBe('Joss');
  });

  it('removes a character and every relationship they are in, in either direction', () => {
    const out = removeMember(story(), 1);
    expect(out.cast.map((m) => m.name)).toEqual(['Mara', 'Teodor']);
    expect(out.relationships).toEqual([]);
  });

  it('keeps relationships between the people who stay', () => {
    const out = removeMember(story(), 2);
    expect(out.relationships.map((r) => `${r.from}>${r.to}`)).toEqual(['Mara>Joss', 'Joss>Mara']);
  });

  it('sets a voice, and an empty id goes back to the default narrator', () => {
    const p = story();
    expect(setVoice(p, 1, 'piper-amy').cast[1].voice_model).toBe('piper-amy');
    expect(setVoice(p, 0, '').cast[0].voice_model).toBeUndefined();
  });

  it('seeds the dialog from the dossier, and from nothing for Add', () => {
    expect(castFields(null)).toEqual({ name: '', role: '', description: '', desire: '', flaw: '' });
    expect(castFields(member('Mara', { role: 'Lead', desire: 'out', flaw: 'pride' }))).toMatchObject({ name: 'Mara', role: 'Lead', desire: 'out', flaw: 'pride' });
  });

  it('words the line under a name from what is known, and nothing from nothing', () => {
    expect(memberMeta(member('Mara', { role: 'Protagonist', desire: 'freedom', flaw: 'pride' }))).toBe('Protagonist · wants freedom · flaw: pride');
    expect(memberMeta(member('Joss', { flaw: 'pride' }))).toBe('flaw: pride');
    expect(memberMeta(member('Teodor'))).toBe('');
  });

  it('shortens a chip to 40 characters and the interview to 420', () => {
    expect(shortText('clipped, dry')).toBe('clipped, dry');
    expect(shortText('x'.repeat(41))).toBe(`${'x'.repeat(40)}…`);
    expect(interviewExcerpt('y'.repeat(420))).toBe('y'.repeat(420));
    expect(interviewExcerpt('y'.repeat(421))).toBe(`${'y'.repeat(420)}…`);
    expect(firstName('Mara Vell')).toBe('Mara');
  });
});
