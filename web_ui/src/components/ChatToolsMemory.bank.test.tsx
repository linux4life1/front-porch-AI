// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 4 (docs/design/one-chat-ux.md): the Memory section carries the desktop
// leaf's three links in its order (Settings, Sources, Data Bank), for the
// focused member, and a group's switch greys out while the global Memory
// setting is off.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const posts: { url: string; body: Record<string, unknown> }[] = [];
let bank = {
  available: true,
  ownerName: 'Mara',
  entries: [{ id: 'e1', title: 'Gate', content: 'The garden gate is blue.', embedded: false }],
  embedded: 0,
  unembedded: 1,
};
let sources = {
  available: true,
  ownerName: 'Mara',
  selected: [] as string[],
  choices: [
    { id: 'Bea_1', name: 'Bea' },
    { id: 'Zoe_1', name: 'Zoe' },
  ],
};

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: (url: string) =>
      url.includes('/memory/sources')
        ? Promise.resolve(sources)
        : url.includes('/memory/databank')
          ? Promise.resolve(bank)
          : new Promise(() => {}),
    post: (url: string, body: Record<string, unknown>) => {
      posts.push({ url, body });
      if (url.includes('/memory/sources')) {
        sources = {
          ...sources,
          selected: body.selected ? [...sources.selected, String(body.id)] : [],
        };
        return Promise.resolve(sources);
      }
      if (body.action === 'add') {
        bank = {
          ...bank,
          entries: [...bank.entries, { id: 'e2', title: String(body.title), content: String(body.content), embedded: false }],
        };
      }
      if (body.action === 'delete') bank = { ...bank, entries: [], unembedded: 0 };
      return Promise.resolve(bank);
    },
  },
}));

const { ChatToolsMemory, MEMORY_OFF_EVERYWHERE } = await import('./ChatToolsMemory');

let container: HTMLDivElement;
let root: Root;

function state(extra: Record<string, unknown> = {}) {
  return {
    memory: {
      ragEnabled: true,
      ragRetrievalCount: 4,
      ragWindowSize: 5,
      journalEnabled: false,
      journalInterval: 10,
      growthEnabled: false,
      growthInterval: 10,
      growthReviewFirst: false,
      embedding: { available: true },
      ...extra,
    },
    summary: { text: '', paused: false, isGenerating: false, lastIndex: 0 },
  };
}

async function render(t: unknown, focusedId: string | null = 'm1') {
  await act(async () => {
    root.render(
      createElement(ChatToolsMemory, { t: t as never, focusedId, reloadKey: 1, settings: vi.fn() }),
    );
    await Promise.resolve();
    await Promise.resolve();
  });
}
const click = async (el: Element) => {
  await act(async () => {
    (el as HTMLElement).click();
    await Promise.resolve();
    await Promise.resolve();
  });
};
const button = (label: RegExp) =>
  [...container.querySelectorAll('button')].find((b) => label.test(b.textContent ?? ''))!;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  sources = { ...sources, selected: [] };
  bank = {
    available: true,
    ownerName: 'Mara',
    entries: [{ id: 'e1', title: 'Gate', content: 'The garden gate is blue.', embedded: false }],
    embedded: 0,
    unembedded: 1,
  };
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Memory section links', () => {
  it('shows Settings, Sources and Data Bank in the desktop order, settings hidden until asked', async () => {
    await render(state());
    const links = [...container.querySelectorAll('.memory-link')].map((b) => b.textContent);
    expect(links).toEqual(['Settings', 'Sources', 'Data Bank']);
    expect(container.textContent).not.toContain('Past moments per reply');
    await click(button(/^Settings$/));
    expect(container.textContent).toContain('Past moments per reply');
  });

  it('Sources lists the other characters and saves each toggle for the focused member', async () => {
    await render(state());
    await click(button(/^Sources/));
    expect(container.textContent).toContain('Include memories from other characters:');
    const box = container.querySelector<HTMLInputElement>('input[aria-label="Include memories from Zoe"]')!;
    await click(box);
    expect(posts.at(-1)).toEqual({
      url: '/api/chat/tools/memory/sources?participant=m1',
      body: { id: 'Zoe_1', selected: true },
    });
    expect(container.textContent).toContain('Sources (1)');
  });

  it('Data Bank lists, adds and deletes entries, and offers Embed while some are not embedded', async () => {
    await render(state());
    await click(button(/^Data Bank$/));
    const modal = container.ownerDocument.querySelector('.data-bank')!;
    expect(modal.textContent).toContain('Data Bank — Mara');
    expect(modal.textContent).toContain('1 entries, 0 embedded, 1 need embedding');
    expect(modal.textContent).toContain('Embed (1)');
    await click([...modal.querySelectorAll('button')].find((b) => b.textContent === 'Add Entry')!);
    const set = (el: HTMLInputElement | HTMLTextAreaElement, v: string) => {
      const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement : HTMLInputElement;
      Object.getOwnPropertyDescriptor(proto.prototype, 'value')!.set!.call(el, v);
      el.dispatchEvent(new Event('input', { bubbles: true }));
    };
    await act(async () => {
      set(modal.querySelector('input')!, 'Roof');
      set(modal.querySelector('textarea')!, 'The roof leaks.');
    });
    await click([...modal.querySelectorAll('button')].find((b) => b.textContent === 'Save')!);
    expect(posts.at(-1)!.body).toMatchObject({ action: 'add', title: 'Roof', content: 'The roof leaks.' });
    expect(posts.at(-1)!.url).toBe('/api/chat/tools/memory/databank?participant=m1');
    expect(modal.textContent).toContain('Roof');
    await click(modal.querySelector('button[aria-label="Delete Gate"]')!);
    expect(posts.at(-1)!.body).toEqual({ action: 'delete', id: 'e1' });
  });
});

describe('a group\'s Memory switch', () => {
  it('greys out with the shared note while the global Memory setting is off', async () => {
    await render(state({ ragScope: 'group', ragGlobalEnabled: false }));
    const sw = container.querySelector<HTMLInputElement>('.tool-toggle input[type="checkbox"]')!;
    expect(sw.disabled).toBe(true);
    expect(container.textContent).toContain(MEMORY_OFF_EVERYWHERE);
    expect(container.querySelector('.memory-link')).toBeNull();
  });

  it('is live when the global setting is on', async () => {
    await render(state({ ragScope: 'group', ragGlobalEnabled: true }));
    const sw = container.querySelector<HTMLInputElement>('.tool-toggle input[type="checkbox"]')!;
    expect(sw.disabled).toBe(false);
    expect(container.querySelector('.memory-link')).not.toBeNull();
  });
});
