// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A small Studio story for the unit tests: three scenes in one act, the first
// written, the second planned, the third not planned. Tests only; the app never imports this.

import type { StoryProject } from '../../storyTypes';

export function studioStory(patch: Record<string, unknown> = {}): StoryProject {
  return {
    id: 's1',
    title: 'The Salt Road',
    concept: 'A courier owes a smuggler forty silver.',
    status_quo: '',
    inciting_incident: '',
    themes: '',
    cast: [{ name: 'Mara' }, { name: 'Joss' }],
    threads: [],
    lore: [],
    acts: [{ number: 1, title: 'The Debt', description: '' }],
    sequences: [{ number: 1, act: 1, title: 'The Ledger', dramatic_question: 'Can she hide it?', summary: '' }],
    scenes: {
      '0': [
        { number: 1, id: 'a', title: 'The ledger', sequence: 1, lens: 'KINETIC_ACTION', cast_names: ['Mara', 'Joss'] },
        { number: 2, id: 'b', title: 'The knock', sequence: 1, lens: 'reflection', cast_names: ['Mara'] },
        { number: 3, id: 'c', title: 'The offer', sequence: 1 },
      ],
    },
    beats: {
      '0-0': [{ number: 1 }, { number: 2 }],
      '0-1': [{ number: 1 }, { number: 2 }, { number: 3 }, { number: 4 }],
    },
    prose: { '0-0-0': { final: 'one two three' }, '0-0-1': { final: 'four five' } },
    engine_mode: 'studio',
    review_enabled: true,
    lenses_enabled: true,
    ...patch,
  } as unknown as StoryProject;
}
