// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Your chats together" on the phone's character editor reads
// /api/characters/<id>/stats and hides itself for a character never chatted
// with. Desktop twin: test/ui/widgets/character_stats_section_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const byId: Record<string, unknown> = {
  mira: {
    chats: 2,
    theirMessages: 40,
    yourMessages: 38,
    theirWords: 1234,
    yourWords: 456,
    longestChat: 60,
    firstChat: '2026-03-01T00:00:00.000',
    lastChat: '2026-09-02T00:00:00.000',
  },
  nobody: {
    chats: 0,
    theirMessages: 0,
    yourMessages: 0,
    theirWords: 0,
    yourWords: 0,
    longestChat: 0,
    firstChat: null,
    lastChat: null,
  },
};
const asked: string[] = [];

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => {
      asked.push(path);
      return Promise.resolve(byId[path.split('/')[3]]);
    },
  },
}));

const { CharacterStatsCard } = await import('./CharacterStatsCard');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  asked.length = 0;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function show(characterId: string) {
  act(() => root.render(createElement(CharacterStatsCard, { characterId })));
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}

it('shows the counts for a character you have chatted with', async () => {
  await show('mira');

  expect(asked).toEqual(['/api/characters/mira/stats']);
  expect(container.textContent).toContain('Your chats together');
  const tiles = [...container.querySelectorAll('.char-stat')].map((t) => t.textContent);
  expect(tiles).toContain(`${(1234).toLocaleString()}Their words`);
  expect(tiles).toContain('60 messagesLongest chat');
  expect(tiles.some((t) => t?.endsWith('First chat'))).toBe(true);
});

it('shows nothing for a character never chatted with', async () => {
  await show('nobody');

  expect(container.textContent).toBe('');
});
