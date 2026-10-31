// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Realism switch for this chat (desktop: the Character State
// header, Group Settings for a group). While Porch Life's Realism Engine is
// off it greys out at the chat's own choice and says where to look; an
// older desktop that sends only realismEnabled keeps today's switch.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

let extra: Partial<ToolsState> = {};
const posts: { path: string; body: unknown }[] = [];

function toolsState(): ToolsState {
  return {
    realismEnabled: true,
    needsEnabled: true,
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
    ...extra,
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
  extra = {};
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

const realismSwitch = () => container.querySelector<HTMLInputElement>('input[aria-label="Realism engine"]');
const NOTE = 'The Realism Engine is off in Porch Life';

it("an older desktop's realismEnabled still drives a live switch", async () => {
  extra = { realismEnabled: false };
  await renderTools();
  expect(realismSwitch()!.checked).toBe(false);
  expect(realismSwitch()!.disabled).toBe(false);
  await act(async () => {
    realismSwitch()!.click();
  });
  expect(posts.map((p) => p.body)).toContainEqual({ name: 'realism', value: true });
  expect(container.textContent).not.toContain(NOTE);
});

it("Porch Life blocking Realism greys the switch at the chat's own choice, with where to look", async () => {
  extra = { realismEnabled: false, realismAllowed: false, realismSwitch: true };
  await renderTools();
  expect(realismSwitch()!.checked).toBe(true);
  expect(realismSwitch()!.disabled).toBe(true);
  expect(container.textContent).toContain(NOTE);
  expect(container.querySelector('input[aria-label="Needs"]')).toBeNull();
});

it('allowed again: the switch is live at its own position', async () => {
  extra = { realismEnabled: true, realismAllowed: true, realismSwitch: true };
  await renderTools();
  expect(realismSwitch()!.checked).toBe(true);
  expect(realismSwitch()!.disabled).toBe(false);
  expect(container.textContent).not.toContain(NOTE);
});
