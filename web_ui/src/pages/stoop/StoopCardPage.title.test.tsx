// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Stoop listing name is the post's title ("Misty Meadows, Misguided
// Meteorologist" for a card named Misty). "Add to library" hands it to the
// relay, which keeps it as the character's title — the desktop detail page
// does the same with the name it shows. Mocked client only, no network.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const { download } = vi.hoisted(() => ({
  download: vi.fn(() => Promise.resolve({ ok: true, name: 'Misty', type: 'SOLO' })),
}));

vi.mock('../../stoop/StoopContext', () => ({ useStoop: () => ({ user: null }) }));
vi.mock('./StoopDiscussion', () => ({ StoopDiscussion: () => null }));
vi.mock('./StoopCardSections', () => ({ StoopCardSections: () => null }));
vi.mock('../../stoop/stoopApi', () => ({
  stoop: {
    cardDetail: () =>
      Promise.resolve({
        id: 'post-1',
        name: 'Misty Meadows, Misguided Meteorologist',
        summary: 'Forecasts badly.',
        type: 'SOLO',
        nsfw: false,
        score: 0,
        downloadCount: 0,
        modPick: false,
        creator: null,
        primaryAssetId: null,
        tokenCount: null,
        version: 1,
        card: { name: 'Misty', description: 'Forecasts badly.' },
        tags: [],
        myVote: 0,
      }),
    download,
  },
  stoopErrorText: (e: unknown) => String(e),
}));

const { StoopCardPage } = await import('./StoopCardPage');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  download.mockClear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('Add to library sends the listing name for the title', async () => {
  await act(async () => {
    root.render(
      createElement(
        MemoryRouter,
        { initialEntries: ['/stoop/card/post-1'] },
        createElement(
          Routes,
          null,
          createElement(Route, { path: '/stoop/card/:id', element: createElement(StoopCardPage) }),
        ),
      ),
    );
  });
  const add = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Add to library');
  expect(add).toBeDefined();
  await act(async () => add!.click());
  expect(download).toHaveBeenCalledWith('post-1', 'SOLO', 'Misty Meadows, Misguided Meteorologist');
});
