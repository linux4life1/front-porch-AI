// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Toggling the Stoop NSFW preference must refetch catalog pages that stay
// mounted (or remount with the same tree). Proven: drop `nsfwEnabled` from
// the browse/home effects and the second-wave fetch count stays flat.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { createElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { stoopState, browseCalls } = vi.hoisted(() => ({
  stoopState: { user: { nsfwEnabled: false } },
  browseCalls: [] as string[],
}));

vi.mock('../../stoop/StoopContext', () => ({
  useStoop: () => stoopState,
}));

vi.mock('../../stoop/stoopApi', () => ({
  stoop: {
    browse: (q: { pick?: boolean; following?: boolean; type?: string }) => {
      const key = q.pick ? 'pick' : q.following ? 'following' : (q.type ?? 'all');
      browseCalls.push(key);
      return Promise.resolve({
        items: [
          {
            id: stoopState.user.nsfwEnabled ? 'adult' : 'sfw',
            name: stoopState.user.nsfwEnabled ? 'Adult Neighbor' : 'Porch Neighbor',
            summary: 'A neighbor on the porch.',
            type: 'SOLO',
            nsfw: stoopState.user.nsfwEnabled,
            score: 0,
            downloadCount: 0,
            modPick: false,
            creator: null,
            primaryAssetId: null,
            tokenCount: null,
          },
        ],
        total: 1,
        page: 0,
      });
    },
  },
  stoopErrorText: (e: unknown) => String(e),
}));

const { StoopBrowsePage } = await import('./StoopBrowsePage');
const { StoopHomePage } = await import('./StoopHomePage');

function wrap(page: ReactNode, path: string) {
  return createElement(
    MemoryRouter,
    { initialEntries: [path] },
    createElement(Routes, null, createElement(Route, { path: '*', element: page })),
  );
}

let container: HTMLDivElement;
let root: Root;

async function renderPage(page: ReactNode, path: string) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(wrap(page, path));
  });
  await act(async () => {
    await Promise.resolve();
  });
}

async function flipNsfw() {
  stoopState.user = { nsfwEnabled: true };
  await act(async () => {
    root.render(wrap(createElement(StoopBrowsePage), '/stoop/browse'));
    await Promise.resolve();
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  stoopState.user = { nsfwEnabled: false };
  browseCalls.length = 0;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Stoop NSFW catalog reload', () => {
  it('refetches browse when Show NSFW cards flips', async () => {
    await renderPage(createElement(StoopBrowsePage), '/stoop/browse');
    const firstWave = browseCalls.length;
    expect(firstWave).toBeGreaterThan(0);
    expect(container.textContent).toContain('Porch Neighbor');

    await flipNsfw();
    expect(browseCalls.length).toBeGreaterThan(firstWave);
    expect(container.textContent).toContain('Adult Neighbor');
  });

  it('refetches home carousels when Show NSFW cards flips', async () => {
    await renderPage(createElement(StoopHomePage), '/stoop');
    const firstWave = browseCalls.length;
    expect(firstWave).toBeGreaterThan(0);

    stoopState.user = { nsfwEnabled: true };
    await act(async () => {
      root.render(wrap(createElement(StoopHomePage), '/stoop'));
      await Promise.resolve();
    });
    expect(browseCalls.length).toBeGreaterThan(firstWave);
  });
});
