// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { studioStory } from '../storyFixture';
import { upNextFor } from './upNext';

const lens = (id: string) => ({ KINETIC_ACTION: 'Kinetic action', REFLECTION: 'Reflection' }[id.toUpperCase()] ?? '');

describe('upNextFor', () => {
  it('asks for the bible when there is no cast and no acts, and says what the run is doing meanwhile', () => {
    const empty = studioStory({ cast: [], acts: [], scenes: {}, beats: {}, prose: {}, sequences: [] });
    const idle = upNextFor(empty, false, '', lens);
    expect(idle).toMatchObject({
      title: 'The bible is not built',
      detail: 'Cast, themes, threads and lore come from your idea.',
      action: 'bible',
      label: 'Build the bible',
      autopilot: false,
    });
    const running = upNextFor(empty, true, 'Asking the model…', lens);
    expect(running.title).toBe('Building the story bible…');
    expect(running.detail).toBe('Asking the model…');
  });

  it('offers the acts once the bible exists', () => {
    const p = studioStory({ acts: [], scenes: {}, beats: {}, prose: {}, sequences: [] });
    expect(upNextFor(p, false, '', lens)).toMatchObject({
      title: 'Bible ready',
      detail: "Next: the acts and the first sequence's scenes.",
      action: 'acts',
      label: 'Build acts',
      autopilot: true,
    });
  });

  it('points at the next unfinished scene: its label, how far it is, its lens and who is in it', () => {
    const up = upNextFor(studioStory(), false, '', lens);
    // 1.1 is written; 1.2 has four planned beats and none written.
    expect(up).toMatchObject({
      title: '1.2 · The knock',
      detail: '4 beats planned · Reflection · Mara',
      action: 'continue',
      label: 'Continue writing',
      sequence: 'Sequence 1 of 1',
      autopilot: true,
      autopilotIdle: false,
    });
  });

  it('counts the beat in progress, and says so when beats are not planned yet', () => {
    const half = studioStory({ prose: { '0-0-0': { final: 'x' }, '0-0-1': { final: 'y' }, '0-1-0': { final: 'z' } } });
    expect(upNextFor(half, false, '', lens).detail).toContain('beat 2 of 4');
    const unplanned = studioStory({
      beats: { '0-0': [{ number: 1 }] },
      prose: { '0-0-0': { final: 'x' } },
    });
    const up = upNextFor(unplanned, false, '', lens);
    expect(up.title).toBe('1.2 · The knock');
    expect(up.detail.startsWith('beats not planned yet')).toBe(true);
  });

  it('leaves the lens out when lenses are off', () => {
    const up = upNextFor(studioStory({ lenses_enabled: false }), false, '', lens);
    expect(up.detail).toBe('4 beats planned · Mara');
  });

  it('a bible still building stays "Building…" once the interviews have filled the cast', () => {
    const midBuild = studioStory({ acts: [], scenes: {}, beats: {}, prose: {}, sequences: [] });
    expect(upNextFor(midBuild, true, 'Reviewing the arc', lens)).toMatchObject({
      title: 'Building the story bible…',
      detail: 'Reviewing the arc',
      action: 'bible',
    });
    expect(upNextFor(midBuild, false, '', lens).title).toBe('Bible ready');
  });

  it('acts with no scenes yet are "Acts ready", not "written" — Continue outlines them', () => {
    const planned = studioStory({ scenes: {}, beats: {}, prose: {} });
    expect(upNextFor(planned, false, '', lens)).toMatchObject({
      title: 'Acts ready',
      action: 'continue',
      label: 'Continue writing',
      autopilotIdle: false,
    });
    // A later sequence still to outline is the same case with a different title.
    const partly = studioStory({
      sequences: [
        { number: 1, act: 1, title: 'The Ledger', dramatic_question: '', summary: '' },
        { number: 2, act: 1, title: 'The Road', dramatic_question: '', summary: '' },
      ],
      scenes: { '0': [{ number: 1, id: 'a', title: 'One', sequence: 1 }] },
      beats: { '0-0': [{ number: 1 }, { number: 2 }] },
    });
    expect(upNextFor(partly, false, '', lens).title).toBe('Next part not outlined yet');
  });

  it('offers Read when every scene is written', () => {
    const done = studioStory({
      scenes: { '0': [{ number: 1, id: 'a', title: 'One', sequence: 1 }] },
      beats: { '0-0': [{ number: 1 }, { number: 2 }] },
    });
    expect(upNextFor(done, false, '', lens)).toMatchObject({
      title: 'The whole story is written',
      detail: '5 words. Read it, or ask the Director for changes.',
      action: 'read',
      label: 'Read',
      autopilotIdle: true,
    });
  });
});
