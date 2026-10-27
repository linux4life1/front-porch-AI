// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "Part of" picker (slice 4 web twin of slice 3). Guards, in order of
// the failure they prevent:
//   - candidates come from the relay's ONE law endpoint, never a client
//     guess (review #592: a UI that re-decides legality drifts);
//   - the save posts parentWorldId, and clearing Part of detaches;
//   - naming a parent flips the place to Inherit (design §7 default);
//   - a dangling/cycled parent still renders a value (the select must be
//     honest about state the relay reports), the web twin of desktop's
//     pinned-item fix;
//   - the library groups children under their root instead of one flat
//     grid, and a library with no tree is the old flat grid untouched.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
const { loreProps } = vi.hoisted(() => ({
  loreProps: { current: null as null | { title?: string; note?: string | null } },
}));
vi.mock('../components/LoreEntriesEditor', () => ({
  LoreEntriesEditor: (p: { title?: string; note?: string | null }) => {
    loreProps.current = p;
    return null;
  },
}));
vi.mock('../components/ImportCharacterLoreButton', () => ({
  ImportCharacterLoreButton: () => null,
}));

import { WorldsPage } from './WorldsPage';

let container: HTMLDivElement;
let root: Root;

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find(
    (b) => b.textContent?.trim() === label,
  )!;

const partOfSelect = () =>
  container.querySelector('select[aria-label="Part of"]') as HTMLSelectElement;

function setValue(el: HTMLSelectElement, value: string) {
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLSelectElement.prototype,
      'value',
    )?.set;
    setter?.call(el, value);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

const WORLD_ROWS = [
  {
    id: 'earth-1',
    name: 'Earth',
    description: 'A world',
    entryCount: 2,
    enabledEntryCount: 1,
    climateEnabled: true,
    biomeId: 'temperate',
  },
  {
    id: 'town-1',
    name: 'Bletchfield',
    description: 'A town',
    entryCount: 1,
    climateEnabled: false,
    parentWorldId: 'earth-1',
  },
];

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    if (url.startsWith('/api/worlds/parent-candidates'))
      return Promise.resolve({
        candidates: [{ id: 'earth-1', name: 'Earth', parentWorldId: null }],
      });
    if (url.includes('/detail'))
      return Promise.resolve({
        id: 'earth-1',
        name: 'Earth',
        description: 'A world',
        entries: [
          { name: 'Sea', key: 'sea', content: 'Salt water.', enabled: true },
          { name: 'Old law', key: 'law', content: 'Repealed.', enabled: false },
        ],
        climateEnabled: true,
        atmosphere: 'breathable',
        gravity: 'earth',
      });
    return Promise.resolve({ worlds: WORLD_ROWS });
  });
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Part of picker', () => {
  it('asks the relay for the candidate law and lists what it answers', async () => {
    await act(async () => button('＋ New place').click());
    expect(
      get.mock.calls.some(([u]) => String(u).startsWith('/api/worlds/parent-candidates')),
    ).toBe(true);
    const sel = partOfSelect();
    expect(sel).not.toBeNull();
    const options = Array.from(sel.querySelectorAll('option')).map((o) => o.textContent);
    expect(options).toContain('Not inside anything (its own world)');
    expect(options).toContain('Earth');
  });

  it('a new place inside a parent defaults to INHERIT, and saves the parent', async () => {
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    // Name it so Save is live (blank-name law), then save.
    const nameInput = container.querySelector(
      '.world-edit label input',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(nameInput, 'The Lighthouse');
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    post.mockResolvedValue({ worlds: WORLD_ROWS });
    await act(async () => button('Add place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({
        name: 'The Lighthouse',
        parentWorldId: 'earth-1',
        // §7: inheritance is the default the moment a parent is named.
        climateEnabled: false,
      }),
    );
  });

  it('clearing Part of detaches on save — never keeps a ghost parent', async () => {
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    setValue(partOfSelect(), '');
    const nameInput = container.querySelector(
      '.world-edit label input',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(nameInput, 'Detached');
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    // Detached, it is a new top-level world: it must name where chats start.
    const startInput = container.querySelector(
      'input[aria-label="Starting place"]',
    ) as HTMLInputElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        window.HTMLInputElement.prototype,
        'value',
      )?.set;
      setter?.call(startInput, 'Detached Square');
      startInput.dispatchEvent(new Event('input', { bubbles: true }));
    });
    post.mockResolvedValue({ worlds: WORLD_ROWS });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({ parentWorldId: null }),
    );
  });

  it('shows a dangling parent honestly instead of blanking', async () => {
    // Editing the town whose parent Earth vanished from candidates.
    get.mockImplementation((url: string) => {
      if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
      if (url.startsWith('/api/worlds/parent-candidates'))
        return Promise.resolve({ candidates: [] });
      if (url.includes('/detail'))
        return Promise.resolve({
          id: 'town-1',
          name: 'Bletchfield',
          description: 'A town',
          entries: [],
          climateEnabled: false,
          parentWorldId: 'ghost-9',
        });
      return Promise.resolve({ worlds: WORLD_ROWS });
    });
    await act(async () => {
      const childCard = Array.from(container.querySelectorAll('.wsg-world-card')).find(
        (c) => c.querySelector('.wsg-world-name')?.textContent === 'Bletchfield',
      )!;
      (childCard.querySelector('[title="Edit"]') as HTMLButtonElement).click();
    });
    const sel = partOfSelect();
    expect(sel.value).toBe('ghost-9');
    expect(Array.from(sel.querySelectorAll('option')).some((o) =>
      (o.textContent ?? '').includes('invalid here'),
    )).toBe(true);
  });
});

describe('the editor wording follows Part of', () => {
  const heading = () => container.querySelector('.world-edit h3')?.textContent;
  const labelTexts = () =>
    Array.from(container.querySelectorAll('.world-edit label')).map((l) =>
      l.textContent?.trim(),
    );

  it('a place inside a parent names the parent, and detaching goes back', async () => {
    await act(async () => button('＋ New place').click());
    expect(heading()).toBe('New place');
    expect(button('Save place')).toBeDefined();

    setValue(partOfSelect(), 'earth-1');
    // Let the parent's detail fetch land: the count must agree either way.
    await act(async () => {});
    expect(heading()).toBe('Add a place to Earth');
    expect(container.textContent).toContain("It shares Earth's lore and climate");
    expect(labelTexts().some((t) => t?.startsWith('Place name'))).toBe(true);
    expect(labelTexts().some((t) => t?.startsWith('Description (place prose)'))).toBe(false);
    expect(button('Add place')).toBeDefined();
    expect(button('Save place')).toBeUndefined();
    // The place's own book, plus the lore its parent chain brings in.
    expect(loreProps.current?.title).toBe("This place's lore");
    expect(loreProps.current?.note).toContain('Also active here: 1 lore entry from Earth.');

    // Own climate opens the climate editor under the Inherit / Own pair.
    const radios = container.querySelector('.wsg-climate-radios')!;
    const ownRadio = radios.querySelectorAll('input[type="radio"]')[1] as HTMLInputElement;
    act(() => ownRadio.click());
    const climateLabel = Array.from(radios.querySelectorAll('label')).find((l) =>
      l.textContent?.trim().startsWith('Climate'),
    );
    expect(climateLabel?.querySelector('select')).not.toBeNull();
    expect(radios.textContent).toContain('Atmosphere');

    setValue(partOfSelect(), '');
    expect(heading()).toBe('New place');
    expect(button('Save place')).toBeDefined();
  });
});

describe('the inherited-lore count', () => {
  it('trusts the fresh list row over a lagging parent detail', async () => {
    // The detail still lists both entries as on (fetched before the parent
    // was edited); the list row, refreshed by that save, says one is on.
    const base = get.getMockImplementation()!;
    get.mockImplementation((url: string) =>
      url.includes('/detail')
        ? Promise.resolve({
            id: 'earth-1',
            name: 'Earth',
            description: 'A world',
            entries: [
              { name: 'Sea', key: 'sea', content: 'Salt water.', enabled: true },
              { name: 'Moon', key: 'moon', content: 'One moon.', enabled: true },
            ],
            climateEnabled: true,
          })
        : base(url),
    );
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    await act(async () => {});
    expect(loreProps.current?.note).toContain('Also active here: 1 lore entry from Earth.');
  });
});

describe('the grouped library', () => {
  it('indents the child under its root, not beside it in a flat grid', () => {
    const grid = container.querySelector('.wsg-child-grid');
    expect(grid).not.toBeNull();
    const childNames = Array.from(
      grid!.querySelectorAll('.wsg-world-name'),
    ).map((n) => n.textContent);
    expect(childNames).toContain('Bletchfield');
    // Earth renders through its section header only — never also flat.
    const sectionHeads = container.querySelectorAll('.wsg-section-head');
    expect(sectionHeads).toHaveLength(1);
  });

  it('a section child keeps its weather tag but drops the redundant inside-tag', () => {
    // The CI journey caught these two being conflated: the weather tag
    // rides the parent (every location gets one); the inside-tag only
    // renders where the tree is not visually obvious. A child under its
    // root is obvious — but still must say what its weather does.
    const grid = container.querySelector('.wsg-child-grid')!;
    const childCard = Array.from(grid.querySelectorAll('.wsg-world-card')).find(
      (c) => c.querySelector('.wsg-world-name')?.textContent === 'Bletchfield',
    )!;
    expect(
      childCard.querySelector('.wsg-weather-tag--inherit')?.textContent,
    ).toBe('Inherits weather');
    expect(childCard.querySelector('.wsg-inside-tag')).toBeNull();
    // The flat 'Solo'-style card would carry the inside-tag; here the
    // root's own card carries the places chip instead.
    expect(
      container
        .querySelector('.wsg-section-head .wsg-place-chip')
        ?.textContent ?? '',
    ).toContain('1 place');
  });

  it('a library with no tree stays the pre-locations flat grid', async () => {
    act(() => root.unmount());
    root = createRoot(container);
    get.mockImplementation((url: string) =>
      Promise.resolve(
        url === '/api/worlds/climates'
          ? { climates: [] }
          : {
              worlds: [
                {
                  id: 'a',
                  name: 'Solo',
                  description: '',
                  entryCount: 0,
                  climateEnabled: true,
                },
              ],
            },
      ),
    );
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
    });
    expect(container.querySelector('.wsg-child-grid')).toBeNull();
    expect(container.querySelectorAll('.wsg-world-card')).toHaveLength(1);
  });
});

describe('a world with weather off', () => {
  it('pauses owned climates inside it and says so in both editors', async () => {
    act(() => root.unmount());
    root = createRoot(container);
    const rows = [
      { ...WORLD_ROWS[0], climateEnabled: false },
      {
        id: 'greenhouse-1',
        name: 'The Greenhouse',
        description: 'Glass rooms',
        entryCount: 0,
        climateEnabled: true,
        biomeId: 'tropical',
        parentWorldId: 'earth-1',
      },
    ];
    get.mockImplementation((url: string) => {
      if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
      if (url.startsWith('/api/worlds/parent-candidates'))
        return Promise.resolve({
          candidates: [{ id: 'earth-1', name: 'Earth', parentWorldId: null }],
        });
      if (url.includes('/detail'))
        return Promise.resolve({
          id: 'earth-1',
          name: 'Earth',
          description: 'A world',
          entries: [],
          climateEnabled: false,
        });
      return Promise.resolve({ worlds: rows });
    });
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
    });

    // The library: an owned climate under a weather-off world is paused.
    const card = Array.from(container.querySelectorAll('.wsg-world-card')).find(
      (c) => c.querySelector('.wsg-world-name')?.textContent === 'The Greenhouse',
    )!;
    expect(card.textContent).toContain('Own climate · paused');
    expect(card.querySelector('.wsg-weather-tag--own')).toBeNull();

    // The place creator says the world's weather is off.
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    await act(async () => {});
    const note = container.querySelector('[data-testid="weather-off-note"]');
    expect(note?.textContent).toContain('Weather is off for Earth');
    const radios = container.querySelector('.wsg-climate-radios')!;
    expect(radios.textContent).toContain('No weather: Earth has weather off.');
    expect(radios.textContent).toContain("No effect while Earth's weather is off");
    const ownRadio = radios.querySelectorAll('input[type="radio"]')[1] as HTMLInputElement;
    act(() => ownRadio.click());
    expect(container.querySelector('[data-testid="climate-paused"]')).not.toBeNull();
    expect(radios.textContent).toContain("Paused while Earth's weather is off");

    // The world's own editor lists the place its switch pauses.
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
    act(() => button('Cancel')!.click());
    const editEarth = container.querySelector(
      '.wsg-section-head button[title="Edit"]',
    ) as HTMLButtonElement;
    await act(async () => editEarth.click());
    await act(async () => {});
    expect(
      container.querySelector('[data-testid="paused-places-note"]')?.textContent,
    ).toContain('1 place inside sets its own climate');
    confirmSpy.mockRestore();
  });
});

describe('weather-off wording in light themes', () => {
  it('keeps the Paused tag and the notes at full ink, outside the dimmed editor', async () => {
    act(() => root.unmount());
    root = createRoot(container);
    const rows = [{ ...WORLD_ROWS[0], climateEnabled: false }];
    get.mockImplementation((url: string) => {
      if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
      if (url.startsWith('/api/worlds/parent-candidates'))
        return Promise.resolve({
          candidates: [{ id: 'earth-1', name: 'Earth', parentWorldId: null }],
        });
      return Promise.resolve({ worlds: rows });
    });
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
    });
    await act(async () => button('＋ New place').click());
    setValue(partOfSelect(), 'earth-1');
    await act(async () => {});
    const radios = container.querySelector('.wsg-climate-radios')!;
    const ownRadio = radios.querySelectorAll('input[type="radio"]')[1] as HTMLInputElement;
    act(() => ownRadio.click());

    const paused = container.querySelector('[data-testid="climate-paused"]')!;
    const tag = paused.querySelector('.wsg-paused-tag')!;
    expect(tag.closest('.wsg-climate-dim')).toBeNull();
    expect(paused.querySelector('.wsg-climate-dim')).not.toBeNull();
    const note = container.querySelector('[data-testid="weather-off-note"]')!;
    expect(note.querySelector('.muted')).toBeNull();
    expect(radios.querySelectorAll('.wsg-weather-off-line')).toHaveLength(2);
  });
});

