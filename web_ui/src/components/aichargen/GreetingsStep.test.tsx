// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web creator's Greetings step (#370): a steered Regenerate asks the relay
// with the steer, shows the text as it streams with Stop while every other
// button and the bar wait, and puts the finished text in the box. Text typed
// into another alternate meanwhile is held, then saved WITH the new greeting
// (saving it earlier would put the old one back over it). Stop leaves the old
// text. Delete takes the alternate and its starting state. Add stops at 5.
// The relay itself is covered against the real app by the browser journey.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { WsEvent } from '../../api/ws';

let emit: (e: WsEvent) => void = () => {};
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: (e: WsEvent) => void) {
      emit = cb;
    }
    connect() {}
    close() {}
  },
}));

type Call = { path: string; body: Record<string, unknown> };
const posts: Call[] = [];
let detail: Record<string, unknown> = {};
vi.mock('../../api/client', () => ({
  api: {
    get: async (path: string) => (path.includes('/detail') ? detail : { writing: null }),
    post: async (path: string, body: Record<string, unknown>) => {
      posts.push({ path, body });
      if (path.endsWith('/stop')) return { stopped: true };
      if (path.endsWith('/delete')) return { firstMessage: '', alternateGreetings: [] };
      return { status: 'started', index: body.index };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { GreetingsStep } = await import('./GreetingsStep');

let container: HTMLDivElement;
let root: Root;
const busy: boolean[] = [];

async function flushAll() {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });
}

const $ = <T extends Element>(sel: string) => {
  const el = container.querySelector<T>(sel);
  if (!el) throw new Error(`missing ${sel}`);
  return el;
};
const card = (i: number) => $(`[data-testid="greeting-card-${i}"]`);
const button = (scope: Element, text: RegExp) => {
  const b = Array.from(scope.querySelectorAll('button')).find((x) => text.test(x.textContent ?? '') || text.test(x.getAttribute('aria-label') ?? ''));
  if (!b) throw new Error(`no button ${text}`);
  return b as HTMLButtonElement;
};
const box = (i: number) => card(i).querySelector('textarea') as HTMLTextAreaElement;

function type(el: HTMLInputElement | HTMLTextAreaElement, value: string) {
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(el, value);
  act(() => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
  await flushAll();
}

beforeEach(async () => {
  vi.useFakeTimers();
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  busy.length = 0;
  detail = {
    firstMessage: '*She trims the wick.* "You came."',
    alternateGreetings: ['ALT ONE', 'ALT TWO'],
    realism: { greetingSeeds: [null, { characterEmotion: 'wistful' }] },
  };
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(GreetingsStep, { characterId: '7', onWritingChange: (w: boolean) => busy.push(w) }));
  });
  await flushAll();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('GreetingsStep', () => {
  it('rewrites, holds other edits, stops, deletes and stops adding at 5', async () => {
    expect(container.querySelector('[data-testid="greeting-count"]')?.textContent).toBe('2 of 5');
    expect(box(0).value).toContain('You came.');

    // A steered Regenerate of alternate 1.
    type(card(1).querySelector('input.cg-g-steer') as HTMLInputElement, 'make it a calm morning');
    await click(button(card(1), /Regenerate/));
    expect(posts.at(-1)).toEqual({
      path: '/api/chargen/greeting',
      body: { characterId: '7', index: 1, direction: 'make it a calm morning' },
    });
    act(() => emit({ event: 'chargen_greeting_progress', characterId: '7', index: 1, text: '*Morning light' }));
    expect(card(1).textContent).toContain('Writing…');
    expect($('[data-testid="greeting-stream"]').textContent).toContain('*Morning light');
    expect(busy.at(-1)).toBe(true);
    expect(button(card(0), /Regenerate/).disabled).toBe(true);
    expect(button(card(2), /Delete alternate 2/).disabled).toBe(true);
    expect(button(container, /Add another greeting/).disabled).toBe(true);

    // Typed into alternate 2 meanwhile: held, not saved over the one being written.
    type(box(2), 'ALT TWO, edited');
    await flushAll();
    expect(posts.filter((p) => p.path === '/api/characters/7')).toHaveLength(0);

    act(() =>
      emit({ event: 'chargen_greeting_done', characterId: '7', index: 1, text: '*Morning light on the jetty.*' }),
    );
    await flushAll();
    expect(busy.at(-1)).toBe(false);
    expect(box(1).value).toBe('*Morning light on the jetty.*');
    expect(posts.at(-1)).toEqual({
      path: '/api/characters/7',
      body: {
        alternateGreetings: ['*Morning light on the jetty.*', 'ALT TWO, edited'],
        greetingSeeds: [null, { characterEmotion: 'wistful' }],
      },
    });

    // Stop leaves the old text.
    await click(button(card(0), /Regenerate/));
    act(() => emit({ event: 'chargen_greeting_progress', characterId: '7', index: 0, text: 'never kept' }));
    await click(button(card(0), /Stop/));
    expect(posts.at(-1)?.path).toBe('/api/chargen/greeting/stop');
    expect(card(0).textContent).not.toContain('Writing…');
    expect(box(0).value).toContain('You came.');
    expect(container.textContent).not.toContain('never kept');
    expect(busy.at(-1)).toBe(false);

    // Delete takes alternate 1 and its (empty) start state; the wistful one stays with ALT TWO.
    await click(button(card(1), /Delete alternate 1/));
    expect(posts.at(-1)).toEqual({ path: '/api/chargen/greeting/delete', body: { characterId: '7', index: 1 } });
    expect(container.querySelector('[data-testid="greeting-count"]')?.textContent).toBe('1 of 5');
    type(box(1), 'ALT TWO, again');
    await flushAll();
    expect(posts.at(-1)?.body).toEqual({
      alternateGreetings: ['ALT TWO, again'],
      greetingSeeds: [{ characterEmotion: 'wistful' }],
    });

    // Add writes until 5, then waits.
    for (let n = 2; n <= 5; n++) {
      await click(button(container, /Add another greeting/));
      expect(posts.at(-1)).toEqual({ path: '/api/chargen/greeting/add', body: { characterId: '7' } });
      expect(card(n).textContent).toContain('Writing…');
      act(() => emit({ event: 'chargen_greeting_done', characterId: '7', index: n, text: `Opening ${n}` }));
      await flushAll();
      expect(box(n).value).toBe(`Opening ${n}`);
    }
    expect(container.querySelector('[data-testid="greeting-count"]')?.textContent).toBe('5 of 5');
    expect(button(container, /Add another greeting/).disabled).toBe(true);
    // Another character's events are not this step's.
    act(() => emit({ event: 'chargen_greeting_done', characterId: '8', index: 1, text: 'not ours' }));
    expect(container.textContent).not.toContain('not ours');
  });
});
