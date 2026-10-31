// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Needs switch for this chat (desktop: the sidebar's Needs line).
// It shows while the chat's Realism is on and greys, with where to look,
// while Porch Life's Needs is off; the chat's own choice is kept.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

let needsAllowed = true;
const posts: { path: string; body: unknown }[] = [];

function toolsState(): ToolsState {
  return {
    realismEnabled: true,
    needsEnabled: false,
    needsAllowed,
    realismOneShotEval: false,
    memory: {
      ragEnabled: false,
      ragRetrievalCount: 3,
      ragWindowSize: 5,
      journalEnabled: false,
      journalInterval: 10,
      growthEnabled: false,
      growthInterval: 10,
      growthReviewFirst: false,
    },
    summary: { text: '', paused: false, isGenerating: false, lastIndex: 0 },
    chaos: { enabled: false, nsfwEnabled: false, pressure: 0, hasPendingEvent: false },
    nsfw: { cooldownEnabled: false, cooldownTurnsRemaining: 0, arousalLevel: 0, arousalTier: '' },
    time: { weekday: 'Tuesday', dayCount: 3, timeOfDay: 'evening', passageEnabled: true, clockRunning: true },
    objectives: { primary: null, secondary: [], isChecking: false },
  };
}

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      /^\/api\/chat\/tools(\?|$)/.test(url) ? Promise.resolve(toolsState()) : new Promise(() => {}),
    post: (path: string, body: unknown) => {
      posts.push({ path, body });
      return new Promise(() => {});
    },
  },
}));

const { ChatTools } = await import('./ChatTools');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  needsAllowed = true;
  posts.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function renderTools() {
  await act(async () => {
    root.render(createElement(ChatTools, { reloadKey: 0 }));
    await new Promise((r) => setTimeout(r, 0));
  });
}

const needsSwitch = () => container.querySelector<HTMLInputElement>('input[aria-label="Needs"]');

it("flipping this chat's Needs switch sends it", async () => {
  await renderTools();
  expect(needsSwitch()!.checked).toBe(false);
  expect(needsSwitch()!.disabled).toBe(false);
  await act(async () => {
    needsSwitch()!.click();
  });
  expect(posts.map((p) => p.body)).toContainEqual({ name: 'needs', value: true });
});

it('greys out with where to look while Porch Life has Needs off', async () => {
  needsAllowed = false;
  await renderTools();
  expect(needsSwitch()!.disabled).toBe(true);
  expect(container.textContent).toContain('Off in Porch Life, so no chat runs Needs.');
});
