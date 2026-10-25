// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-Shot Eval sits directly above the tool-calling pill in the insight
// panel, shows the host's mode, and a click saves the new one. Desktop twin:
// the One-Shot step in integration_test/sidebar_sweep_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

const { post } = vi.hoisted(() => ({ post: vi.fn() }));
let hostMode = 'off';

// The tools snapshot answers; the panel's other loads never settle.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url === '/api/chat/tools'
        ? Promise.resolve({ realismOneShotMode: hostMode, realismOneShotEval: hostMode === 'on' })
        : new Promise(() => {}),
    post,
  },
}));
// The tools list reads the same snapshot in full; it is not part of this pin.
vi.mock('./ChatTools', () => ({ ChatTools: () => null }));

const { ChatInsight } = await import('./ChatInsight');

const realism = {
  realismEnabled: true,
  bond: { score: 12, tier: 'Friendly', percent: 0.52 },
  longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
  trust: { level: 8, tier: 'Some', percent: 0.54 },
  arousal: { level: 0, tier: 'Calm' },
  emotion: 'calm',
  emotionIntensity: 'mild',
  mood: 'calm',
  needs: {},
} as unknown as Realism;

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

async function renderInsight() {
  await act(async () => {
    root.render(
      createElement(ChatInsight, {
        realism,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: false,
        focusedIsHost: false,
        toolsKey: 0,
        focusedId: null,
        groupId: null,
        onCommand: () => {},
        toolSupport: { state: 'supported', testing: false },
      }),
    );
    await new Promise((r) => setTimeout(r, 0));
  });
}

const radio = (name: string) =>
  [...container.querySelectorAll<HTMLButtonElement>('.one-shot-row [role="radio"]')].find(
    (b) => b.textContent === name,
  )!;

describe('One-Shot Eval above the tool-calling pill', () => {
  it('sits right before the pill and shows the host mode', async () => {
    hostMode = 'off';
    await renderInsight();
    const row = container.querySelector('.one-shot-row');
    expect(row).not.toBeNull();
    expect(row?.nextElementSibling?.classList.contains('tool-pill')).toBe(true);
    expect(radio('Off').getAttribute('aria-checked')).toBe('true');
    expect(radio('Auto').getAttribute('aria-checked')).toBe('false');
  });

  it('saves the clicked mode and shows the answer', async () => {
    hostMode = 'auto';
    post.mockResolvedValue({ realismOneShotMode: 'on', realismOneShotEval: true });
    await renderInsight();
    await act(async () => {
      radio('On').dispatchEvent(new MouseEvent('click', { bubbles: true }));
    });
    expect(post).toHaveBeenCalledWith('/api/chat/tools/toggle', {
      name: 'oneShotMode',
      value: 'on',
    });
    expect(radio('On').getAttribute('aria-checked')).toBe('true');
  });
});
