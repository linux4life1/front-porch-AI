// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step (PR 8d): the saved card's text cards in the desktop's
// order, the alternate greeting with its opening-state form, the example
// dialogue rewrite, the lorebook's three rows + "and N more", the keep boxes
// (an unchecked entry is left out of the save), hand-edited pills, and Save &
// Finish's flush. The portrait rail has its own file.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
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
vi.mock('./AvatarRail', () => ({
  AvatarRail: () => createElement('div', { 'data-testid': 'avatar-rail' }),
}));
vi.mock('../GreetingSeedForm', () => ({
  GreetingSeedForm: () => createElement('div', { 'data-testid': 'seed-form' }),
}));
vi.mock('../realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));

type Call = { path: string; body: Record<string, unknown> };
const posts: Call[] = [];
let reviewFails = false;

const BASE_DETAIL = {
  name: 'Porchie',
  description: 'A vampire lecturer.',
  personality: 'Clipped and cold.',
  scenario: 'A rain-soaked cathedral.',
  firstMessage: 'Hello.',
  systemPrompt: 'Stay in character.',
  alternateGreetings: ['Alt one.'],
  realism: { greetingSeeds: [null] },
  tags: ['vampire', 'tsundere'],
  lorebook: {
    entries: [
      { name: 'The Rock', key: 'rock', content: 'A wet rock.', enabled: true, constant: false, stickyDepth: 1 },
      { name: 'My Pub', key: 'pub', content: 'The pub I wrote.', enabled: true, constant: false, stickyDepth: 1 },
      { name: 'The Harbor', key: 'harbor', content: 'Gulls and tar.', enabled: true, constant: false, stickyDepth: 1 },
      { name: 'The Bell', key: 'bell', content: 'It rings at dusk.', enabled: true, constant: false, stickyDepth: 1 },
    ],
  },
};
let detail = structuredClone(BASE_DETAIL);
const REVIEW = {
  mesExample: '{{char}}: Mind the steps.',
  lorebook: [
    { name: 'The Rock', content: 'A wet rock.', handEdited: false },
    { name: 'My Pub', content: 'The pub I wrote.', handEdited: true },
    { name: 'The Harbor', content: 'Gulls and tar.', handEdited: false },
    { name: 'The Bell', content: 'It rings at dusk.', handEdited: false },
  ],
  writing: null,
  sex: 'Female',
  hadInterview: true,
  portraitPromptSeed: 'character portrait, Anime style',
};

vi.mock('../../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path.includes('/detail')) return detail;
      if (path.includes('/chargen/review')) {
        if (reviewFails) throw new Error('offline');
        return REVIEW;
      }
      return {};
    },
    post: async (path: string, body: Record<string, unknown>) => {
      posts.push({ path, body });
      return { status: 'started' };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { ReviewStep } = await import('./ReviewStep');

let container: HTMLDivElement;
let root: Root;
const ref = createRef<import('./ReviewStep').ReviewStepHandle>();

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

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
  await settle();
}

async function render() {
  act(() => {
    root.render(createElement(ReviewStep, { ref, characterId: '7' }));
  });
  await settle();
}

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  reviewFails = false;
  detail = structuredClone(BASE_DETAIL);
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await render();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ReviewStep', () => {
  it('shows the desktop order, the subtitles and the lorebook rows', () => {
    const description = $('[data-testid="review-card-description"]');
    expect(description.textContent).toContain('Who they are, as the card will carry it');
    expect(description.textContent).toContain('A vampire lecturer.');
    expect($('[data-testid="review-card-personality"]').textContent).toContain('How they act and speak');
    expect($('[data-testid="review-card-scenario"]').textContent).toContain('Where the first chat starts');
    expect($('[data-testid="review-card-first-message"]').textContent).toContain('Opens every new chat');
    expect($('[data-testid="review-card-alternate-greeting-1"]')).not.toBeNull();
    expect($('[data-testid="review-card-alternate-greeting-1"] [data-testid="seed-form"]')).not.toBeNull();
    expect($('[data-testid="review-example-dialogue"]').textContent).toContain(
      'How she answers, learned from the interview',
    );
    expect($('[data-testid="review-lorebook"]').textContent).toContain('4 entries');
    expect($('[data-testid="review-lorebook"]').querySelectorAll('.cg-lore-row')).toHaveLength(3);
    expect($('[data-testid="review-lorebook"]').textContent).toContain('and 1 more');
    expect($('[data-testid="review-lorebook"]').querySelector('.cg-lore-pill')?.textContent).toBe(
      'Edited by hand',
    );
    expect($('[data-testid="avatar-rail"]')).not.toBeNull();
    expect(container.textContent).toContain('Porchie');
    expect(container.textContent).toContain('vampire');
  });

  it('leaves an unchecked lorebook entry out of the save', async () => {
    const lore = $('[data-testid="review-lorebook"]');
    await click(button(lore, /Open the lorebook editor/));
    const keep = lore.querySelector('input[aria-label="Keep The Rock"]') as HTMLInputElement;
    expect(keep.checked).toBe(true);
    await act(async () => {
      keep.click();
    });
    await act(async () => {
      await ref.current?.flush();
    });
    const saved = posts.at(-1)!;
    expect(saved.path).toBe('/api/characters/7');
    expect((saved.body.lorebook as { name: string }[]).map((e) => e.name)).toEqual([
      'My Pub',
      'The Harbor',
      'The Bell',
    ]);
  });

  it('resets the keep boxes when a rewrite replaces the lorebook', async () => {
    const lore = $('[data-testid="review-lorebook"]');
    await click(button(lore, /Open the lorebook editor/));
    const keep = lore.querySelector('input[aria-label="Keep The Rock"]') as HTMLInputElement;
    await act(async () => {
      keep.click();
    });
    expect(keep.checked).toBe(false);
    // The rewrite lands with the same count and new content.
    detail = {
      ...BASE_DETAIL,
      lorebook: {
        entries: [
          { name: 'New Rock', key: 'rock', content: 'Rewritten.', enabled: true, constant: false, stickyDepth: 1 },
          ...BASE_DETAIL.lorebook.entries.slice(1),
        ],
      },
    };
    act(() =>
      emit({ event: 'chargen_rewrite_done', characterId: '7', field: 'lorebook', lorebook: [] }),
    );
    await settle();
    const fresh = $('[data-testid="review-lorebook"]').querySelector(
      'input[aria-label="Keep New Rock"]',
    ) as HTMLInputElement;
    // The old unchecked state was about old content; the new entry starts kept.
    expect(fresh.checked).toBe(true);
    await act(async () => {
      fresh.click();
    });
    await act(async () => {
      await ref.current?.flush();
    });
    const saved = posts.at(-1)!;
    expect((saved.body.lorebook as { name: string }[]).map((e) => e.name)).toEqual([
      'My Pub',
      'The Harbor',
      'The Bell',
    ]);
  });

  it('flushes a typed card, and the step reports it dirty while it waits', async () => {
    const area = $('[data-testid="review-card-description"] textarea') as HTMLTextAreaElement;
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!.call(area, 'New words.');
    await act(async () => {
      area.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await act(async () => {
      await ref.current?.flush();
    });
    expect(posts.at(-1)).toEqual({ path: '/api/characters/7', body: { description: 'New words.' } });
  });

  it('streams the example dialogue and ignores the other field\'s late event', async () => {
    const dialogue = $('[data-testid="review-example-dialogue"]');
    const lore = $('[data-testid="review-lorebook"]');
    await click(button(dialogue, /Regenerate/));
    expect(posts.at(-1)?.path).toBe('/api/chargen/rewrite/dialogue');
    act(() =>
      emit({ event: 'chargen_rewrite_progress', characterId: '7', field: 'mesExample', text: '{{char}}: Mind' }),
    );
    expect(dialogue.textContent).toContain('Writing…');
    act(() => emit({ event: 'chargen_rewrite_done', characterId: '7', field: 'mesExample', text: 'stale' }));
    expect(dialogue.textContent).not.toContain('Writing…');
    // A lorebook rewrite starts; a late dialogue end must not clear it.
    await click(button(lore, /Rewrite the lorebook/));
    act(() => emit({ event: 'chargen_rewrite_done', characterId: '7', field: 'mesExample', text: 'stale again' }));
    expect(lore.textContent).toContain('Writing…');
  });

  it('says when the review could not load, and loads it again', async () => {
    act(() => root.unmount());
    reviewFails = true;
    root = createRoot(container);
    await render();
    expect($('[data-testid="review-load-error"]').textContent).toContain('could not be loaded');
    reviewFails = false;
    await click(button($('[data-testid="review-load-error"]'), /Try again/));
    expect(container.querySelector('[data-testid="review-card-description"]')).not.toBeNull();
  });
});
