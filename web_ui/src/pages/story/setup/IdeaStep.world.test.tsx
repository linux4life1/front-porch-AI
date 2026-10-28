// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Idea step's "Where does it happen?" card (docs/design/stories-in-worlds.md
// §5): the picker lists the library as a tree, picking a world starts the
// story at its starred place and the card shows the relay's line, Remove
// clears it. Web twin of test/ui/story_setup/story_world_card_test.dart.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const worlds = [
  { id: 'g', name: 'Greenhollow Estate', description: 'An estate.', entryCount: 6, enabledEntryCount: 6, climateEnabled: true, defaultPlaceId: 'conservatory' },
  { id: 'conservatory', name: 'The Conservatory', description: 'Glass.', entryCount: 2, enabledEntryCount: 2, parentWorldId: 'g' },
  { id: 'kitchens', name: 'The Kitchens', description: 'Flagstones.', entryCount: 2, enabledEntryCount: 2, parentWorldId: 'g' },
];
const summaries: Record<string, object> = {
  conservatory: {
    ok: true, placeId: 'conservatory', worldName: 'Greenhollow Estate', startName: 'The Conservatory', atLarge: false,
    placeCount: 2, factCount: 10, constantCount: 0, searchableCount: 10, climate: 'Mediterranean',
    detail: 'starts at The Conservatory · 2 places · 10 facts · Mediterranean', briefLine: 'World brief: 2 places · 0 always-on facts · 10 searchable facts',
    setInLine: 'Set in Greenhollow Estate · starts at The Conservatory', places: [],
  },
  kitchens: {
    ok: true, placeId: 'kitchens', worldName: 'Greenhollow Estate', startName: 'The Kitchens', atLarge: false,
    placeCount: 2, factCount: 10, constantCount: 0, searchableCount: 10, climate: 'Mediterranean',
    detail: 'at The Kitchens · 2 places · 10 facts · Mediterranean', briefLine: '', setInLine: '', places: [],
  },
};
const asked: string[] = [];

vi.mock('../../../api/client', () => ({
  api: {
    avatarUrl: (path: string) => path,
    get: (path: string) => {
      asked.push(path);
      if (path === '/api/worlds') return Promise.resolve({ worlds });
      if (path.startsWith('/api/stories/world?place=')) {
        const id = decodeURIComponent(path.slice('/api/stories/world?place='.length));
        return Promise.resolve(summaries[id] ?? { ok: false });
      }
      if (path.startsWith('/api/stories/archetypes')) return Promise.resolve({ archetypes: [] });
      return Promise.reject(new Error(`unexpected ${path}`));
    },
  },
}));

const { IdeaStep } = await import('./IdeaStep');
const { emptyDraft } = await import('./draft');
type Draft = ReturnType<typeof emptyDraft>;

let container: HTMLDivElement;
let root: Root;
let latest: Draft;

/** The wizard page's state, in miniature: the step edits a draft it is handed back. */
function Harness({ start }: { start: Draft }) {
  const [draft, setDraft] = useState(start);
  latest = draft;
  return createElement(IdeaStep, { draft, set: setDraft, chars: [], userName: 'Sam' });
}

const flush = () => act(async () => { await Promise.resolve(); await Promise.resolve(); });
const click = (testid: string) => act(async () => {
  const el = document.querySelector<HTMLButtonElement>(`[data-testid="${testid}"]`);
  if (!el) throw new Error(`no ${testid}`);
  el.click();
});
const text = (testid: string) => document.querySelector(`[data-testid="${testid}"]`)?.textContent ?? null;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  asked.length = 0;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Where does it happen?', () => {
  it('picking a world starts the story at its starred place; Remove clears it', async () => {
    await act(async () => root.render(createElement(Harness, { start: emptyDraft() })));
    await flush();
    expect(text('story-world-card')).toContain('Where does it happen?');
    expect(document.querySelector('[data-testid="story-choose-world"]')).not.toBeNull();

    await click('story-choose-world');
    await flush();
    const picker = document.querySelector('[data-testid="story-world-picker"]');
    expect(picker?.textContent).toContain('Greenhollow Estate');
    expect(picker?.textContent).toContain('The Kitchens');
    expect(picker?.textContent).toContain('starts at The Conservatory');

    await click('story-world-row-g');
    await flush();
    expect(asked).toContain('/api/stories/world?place=conservatory');
    expect(latest.world).toMatchObject({ placeId: 'conservatory', worldName: 'Greenhollow Estate', fromChat: false });
    expect(text('story-world-name')).toBe('Greenhollow Estate');
    expect(text('story-world-detail')).toBe('starts at The Conservatory · 2 places · 10 facts · Mediterranean');
    expect(document.querySelector('[data-testid="story-world-picker"]')).toBeNull();

    await click('story-remove-world');
    expect(latest.world).toBeNull();
    expect(document.querySelector('[data-testid="story-choose-world"]')).not.toBeNull();
  });

  it('picking a place inside starts the story there', async () => {
    await act(async () => root.render(createElement(Harness, { start: emptyDraft() })));
    await click('story-choose-world');
    await flush();
    await click('story-world-row-kitchens');
    await flush();
    expect(latest.world).toMatchObject({ placeId: 'kitchens' });
    expect(text('story-world-detail')).toContain('at The Kitchens');
  });

  it('a reopened story asks the relay for its card line, and a gone world says so', async () => {
    const start = { ...emptyDraft(), world: { placeId: 'conservatory', worldName: 'Greenhollow Estate', detail: '', briefLine: '', fromChat: false } };
    await act(async () => root.render(createElement(Harness, { start })));
    await flush();
    expect(text('story-world-detail')).toContain('starts at The Conservatory');

    act(() => root.unmount());
    root = createRoot(container);
    const gone = { ...emptyDraft(), world: { placeId: 'nowhere', worldName: 'Lost Reach', detail: '', briefLine: '', fromChat: false } };
    await act(async () => root.render(createElement(Harness, { start: gone })));
    await flush();
    expect(text('story-world-name')).toBe('Lost Reach');
    expect(text('story-world-detail')).toBe('no longer in the library');
  });
});
