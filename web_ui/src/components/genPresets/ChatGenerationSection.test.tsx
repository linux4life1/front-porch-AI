// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Generation for this chat" in the chat settings drawer (issue 686): the
// desktop's Chat Settings Generation section on the phone. A chat follows
// the model until a value or a preset of its own is set; only a value the
// chat owns has a ↺, which hands it back to the global one; the sliders
// this backend does not carry stay hidden, as in Settings; and the same
// section serves a group chat.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, put, post } = vi.hoisted(() => ({ get: vi.fn(), put: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, put, post }, ApiError: class extends Error {} }));
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

import { ChatGenerationSection } from './ChatGenerationSection';

const GLOBAL = {
  temperature: 0.7, minP: 0.1, topP: 0.9, topK: 0, repeatPenalty: 1.1, repeatPenaltyTokens: 1024,
  xtcThreshold: 0.1, xtcProbability: 0, dryMultiplier: 0, dynamicTempEnabled: false,
  dynamicTempRange: 0.7, maxLength: 2048, reasoningEnabled: false, reasoningEffort: 'medium',
  stopSequences: [],
};

const chatOf = (over: Record<string, unknown> = {}) => ({
  open: true,
  isGroup: false,
  values: {},
  overrides: 0,
  genPresetName: null,
  global: GLOBAL,
  backend: 'openRouter',
  samplerKnobs: ['minP', 'topK', 'repeatPenalty'],
  ...over,
});

let container: HTMLDivElement;
let root: Root;

async function open(chat: Record<string, unknown>) {
  get.mockImplementation(async (path: string) => {
    if (path === '/api/chat/generation') return chat;
    if (path === '/api/gen-presets') {
      return { presets: [{ name: 'Warm', values: { temperature: 1.1 } }], linked: 'Precise' };
    }
    throw new Error(`unexpected GET ${path}`);
  });
  await act(async () => {
    root.render(createElement(ChatGenerationSection));
  });
}

const labels = () =>
  [...container.querySelectorAll('.slider-head > span:first-child')].map((e) => e.textContent);
const resetOf = (label: string) =>
  container.querySelector<HTMLButtonElement>(`button[aria-label^="${label}:"]`);

beforeEach(() => {
  vi.useFakeTimers();
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  put.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('Generation for this chat', () => {
  it('follows the model, shows only what this backend carries', async () => {
    await open(chatOf());
    expect(container.textContent).toContain('Generation for this chat');
    expect(container.textContent).toContain('Following the model');
    const select = container.querySelector<HTMLSelectElement>('select[aria-label="Preset for this chat"]')!;
    expect(select.options[0].textContent).toBe('Follow the model: “Precise”');
    expect(labels()).toEqual([
      'Temperature', 'Min-P', 'Top-P', 'Top-K', 'Repeat penalty', 'Max output tokens',
      'Stop sequences (one per line)',
    ]);
    expect(container.textContent).not.toContain('Dynamic temperature');
    expect(resetOf('Temperature'), 'nothing of its own to hand back').toBeNull();
  });

  it('a value of its own has ↺, which hands it back to the global one', async () => {
    await open(chatOf({ values: { temperature: 1.3 }, overrides: 1 }));
    const value = container.querySelector<HTMLInputElement>('.slider-val')!;
    expect(value.value).toBe('1.3');
    const reset = resetOf('Temperature')!;
    expect(reset.title).toBe('Use the global value (0.7)');
    put.mockResolvedValue(chatOf());
    await act(async () => {
      reset.click();
    });
    await act(async () => {
      vi.advanceTimersByTime(400);
    });
    expect(put).toHaveBeenCalledWith('/api/chat/generation', { values: { temperature: null } });
    expect(resetOf('Temperature')).toBeNull();
  });

  it('a drag is sent once it settles, as one change', async () => {
    await open(chatOf());
    put.mockResolvedValue(chatOf({ values: { temperature: 1 } }));
    const range = container.querySelector<HTMLInputElement>('input[type="range"]')!;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    for (const v of ['0.8', '0.9', '1']) {
      await act(async () => {
        setter.call(range, v);
        range.dispatchEvent(new Event('input', { bubbles: true }));
      });
    }
    expect(put).not.toHaveBeenCalled();
    await act(async () => {
      vi.advanceTimersByTime(400);
    });
    expect(put.mock.calls).toEqual([['/api/chat/generation', { values: { temperature: 1 } }]]);
  });

  it('loads a preset into the chat, and Follow the model clears it', async () => {
    await open(chatOf());
    post.mockResolvedValueOnce(
      chatOf({ values: { temperature: 1.1 }, overrides: 1, genPresetName: 'Warm' }),
    );
    const select = container.querySelector<HTMLSelectElement>('select[aria-label="Preset for this chat"]')!;
    await act(async () => {
      select.value = 'Warm';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(post).toHaveBeenCalledWith('/api/chat/generation/preset', { name: 'Warm' });
    expect(container.textContent).toContain('Using “Warm”');

    post.mockResolvedValueOnce(chatOf());
    await act(async () => {
      select.value = '';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(post).toHaveBeenLastCalledWith('/api/chat/generation/preset', { name: null });
    expect(container.textContent).toContain('Following the model');
  });

  it('serves a group chat the same way, and hides with no chat open', async () => {
    await open(chatOf({ isGroup: true, values: { maxLength: 300 }, overrides: 1 }));
    expect(resetOf('Max output tokens')).not.toBeNull();
    act(() => root.unmount());
    root = createRoot(container);
    await open({ open: false });
    expect(container.textContent).toBe('');
  });
});
