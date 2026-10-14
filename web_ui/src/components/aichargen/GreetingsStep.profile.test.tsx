// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Greetings step after the Profile step. When the relay says the
// profile changed since the greetings were written, the hint offers to
// write them all again (each card is written in turn, the step waits, the
// hint goes when the relay says they were rewritten) or to keep them. At the
// foot, the example dialogue and the lorebook can be steered and rewritten;
// the lorebook card lists its first entries, marks the hand-edited ones and
// counts the rest. (Its own file: the Greetings test's relay stand-in has
// no profile or review answers.) The relay itself is covered by its routes
// test and the browser journey.

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
let profileChanged = true;
const LORE = [
  { name: 'The Rock', content: 'A wet rock two miles out.', handEdited: false },
  { name: 'My Pub', content: 'The pub I wrote myself.', handEdited: true },
  { name: 'The Harbor', content: 'Gulls and tar.', handEdited: false },
  { name: 'The Bell', content: 'It rings at dusk.', handEdited: false },
];
vi.mock('../../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path.includes('/detail')) return { firstMessage: '*She trims the wick.*', alternateGreetings: ['ALT ONE'] };
      if (path.includes('/greeting/status')) return { writing: null, profileChanged };
      if (path.includes('/chargen/review')) {
        return { mesExample: '{{user}}: Hi\n{{char}}: Mind the steps.', lorebook: LORE, writing: null, sex: 'Female' };
      }
      return {};
    },
    post: async (path: string, body: Record<string, unknown>) => {
      posts.push({ path, body });
      if (path.endsWith('/rewrite-all')) return { status: 'started', count: 2 };
      if (path.endsWith('/keep-profile')) return { ok: true };
      return { status: 'started' };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { GreetingsStep } = await import('./GreetingsStep');

let container: HTMLDivElement;
let root: Root;
const busy: boolean[] = [];

async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}

const $ = <T extends Element>(sel: string) => {
  const el = container.querySelector<T>(sel);
  if (!el) throw new Error(`missing ${sel}`);
  return el;
};
const button = (scope: Element, text: RegExp) => {
  const b = Array.from(scope.querySelectorAll('button')).find(
    (x) => text.test(x.textContent ?? '') || text.test(x.getAttribute('aria-label') ?? ''),
  );
  if (!b) throw new Error(`no button ${text}`);
  return b as HTMLButtonElement;
};
const card = (i: number) => $(`[data-testid="greeting-card-${i}"]`);
const hint = () => container.querySelector('[data-testid="creator-hint"]');

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
  await settle();
}

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  busy.length = 0;
  profileChanged = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(GreetingsStep, { characterId: '7', onWritingChange: (w: boolean) => busy.push(w) }));
  });
  await settle();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('GreetingsStep after the Profile step', () => {
  it('rewrites every greeting from the changed profile, one after another', async () => {
    expect(hint()?.textContent).toContain('The profile changed');
    expect(hint()?.textContent).toContain(
      'These greetings were written from the old Description and Personality. Nothing was changed for you.',
    );
    await click(button(hint()!, /Rewrite the greetings from it/));
    expect(posts.at(-1)).toEqual({ path: '/api/chargen/greeting/rewrite-all', body: { characterId: '7' } });
    expect(hint()).toBeNull();
    expect(card(0).textContent).toContain('Writing…');
    expect(busy.at(-1)).toBe(true);
    expect(button(card(1), /Regenerate/).disabled).toBe(true);

    act(() => emit({ event: 'chargen_greeting_progress', characterId: '7', index: 0, text: 'New first' }));
    act(() => emit({ event: 'chargen_greeting_done', characterId: '7', index: 0, text: 'New first.' }));
    expect(card(1).textContent).toContain('Writing…');
    expect(busy.at(-1)).toBe(true);
    act(() => emit({ event: 'chargen_greeting_done', characterId: '7', index: 1, text: 'New alt.' }));
    act(() => emit({ event: 'chargen_greetings_rewritten', characterId: '7' }));
    expect(busy.at(-1)).toBe(false);
    expect(hint()).toBeNull();
    expect((card(1).querySelector('textarea') as HTMLTextAreaElement).value).toBe('New alt.');
  });

  it('keeps the greetings as they are', async () => {
    await click(button(hint()!, /Keep them/));
    expect(posts.at(-1)).toEqual({ path: '/api/chargen/greeting/keep-profile', body: { characterId: '7' } });
    expect(hint()).toBeNull();
  });

  it('steers the example dialogue and the lorebook; hand edits are marked', async () => {
    const dialogue = $('[data-testid="review-example-dialogue"]');
    const lore = $('[data-testid="review-lorebook"]');
    expect(dialogue.textContent).toContain('How she answers, learned from the interview');
    expect(lore.textContent).toContain('4 entries');
    expect(lore.querySelectorAll('.cg-lore-row')).toHaveLength(3);
    expect(lore.textContent).toContain('and 1 more');
    expect(lore.querySelector('.cg-lore-pill')?.textContent).toBe('Edited by hand');

    const steer = dialogue.querySelector('input.cg-g-steer') as HTMLInputElement;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(steer, 'shorter lines');
    act(() => {
      steer.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await click(button(dialogue, /Regenerate/));
    expect(posts.at(-1)).toEqual({
      path: '/api/chargen/rewrite/dialogue',
      body: { characterId: '7', direction: 'shorter lines' },
    });
    act(() =>
      emit({ event: 'chargen_rewrite_progress', characterId: '7', field: 'mesExample', text: '{{char}}: Mind' }),
    );
    expect(dialogue.textContent).toContain('Writing…');
    expect(busy.at(-1)).toBe(true);
    expect(button(lore, /Rewrite the lorebook/).disabled).toBe(true);
    expect(button(card(0), /Regenerate/).disabled).toBe(true);
    act(() =>
      emit({ event: 'chargen_rewrite_done', characterId: '7', field: 'mesExample', text: '{{char}}: Mind it.' }),
    );
    expect(busy.at(-1)).toBe(false);
    expect((dialogue.querySelector('textarea') as HTMLTextAreaElement).value).toBe('{{char}}: Mind it.');

    await click(button(lore, /Rewrite the lorebook/));
    expect(posts.at(-1)?.path).toBe('/api/chargen/rewrite/lorebook');
    act(() =>
      emit({
        event: 'chargen_rewrite_done',
        characterId: '7',
        field: 'lorebook',
        lorebook: [
          { name: 'New Rock', content: 'Rewritten.', handEdited: false },
          { name: 'My Pub', content: 'The pub I wrote myself.', handEdited: true },
        ],
      }),
    );
    expect(lore.textContent).toContain('2 entries');
    expect(lore.textContent).toContain('New Rock');
    expect(lore.querySelector('.cg-lore-pill')?.textContent).toBe('Edited by hand');
  });

  it('shows no hint when the profile is unchanged', async () => {
    act(() => root.unmount());
    profileChanged = false;
    root = createRoot(container);
    act(() => {
      root.render(createElement(GreetingsStep, { characterId: '7' }));
    });
    await settle();
    expect(hint()).toBeNull();
  });
});
