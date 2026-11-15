// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The persona page's card grid is the desktop's page (persona_main_view.dart
// + persona_list_cards.dart): a hero card for the default persona, an
// "All Personas (N)" section, cards with the name subtitle only when a title
// exists, description previews with the desktop's "No description" fallback,
// "Make default" on the rest (tap = set default), and Delete only while
// more than one persona exists.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn();
const get = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => get(path),
    post: (path: string, body?: unknown) => post(path, body),
    upload: vi.fn(),
    getForFile: vi.fn(),
  },
  ApiError: class ApiError extends Error {
    constructor(message: string, readonly status: number) {
      super(message);
    }
  },
}));

import { PersonaManager } from './PersonaManager';

const personas = [
  {
    id: 'p1', label: 'Ada', name: 'Ada Lovelace', title: 'Mathematician',
    description: '{{user}} writes poetry about steam engines.',
    hasAvatar: true, active: true, default: true,
  },
  {
    id: 'p2', label: 'Kit', name: 'Kit', title: '',
    description: '', hasAvatar: false, active: false, default: false,
  },
];

describe('PersonaManager card grid (desktop parity)', () => {
  let root: Root;
  let host: HTMLDivElement;

  beforeEach(() => {
    post.mockReset();
    get.mockReset().mockResolvedValue({ personas });
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
  });

  afterEach(() => {
    act(() => root.unmount());
    host.remove();
    document.body.innerHTML = '';
  });

  const flush = () => act(async () => { await Promise.resolve(); });
  const render = async () => {
    await act(async () => {
      root.render(createElement(PersonaManager));
    });
    await flush();
  };
  const card = (label: string) =>
    [...host.querySelectorAll('.persona-grid li')].find(
      (li) => li.querySelector('.pname')?.textContent === label,
    )!;

  it('shows the hero for the default persona and counts in the section label', async () => {
    await render();
    const hero = host.querySelector('.persona-hero')!;
    expect(hero.textContent).toContain('Ada');
    expect(hero.textContent).toContain('Default');
    // The desktop's people chip: "2 personas".
    expect(host.querySelector('.persona-chip')?.textContent).toContain('2 personas');
    expect(host.querySelector('.persona-section')?.textContent).toContain('All Personas (2)');
  });

  it('paints the name subtitle only with a title and clamps empty copy to the desktop line', async () => {
    await render();
    expect(card('Ada').querySelector('.psub')?.textContent).toBe('Ada Lovelace');
    expect(card('Ada').querySelector('.persona-desc')?.textContent).toContain('steam engines');
    expect(card('Kit').querySelector('.psub')).toBeNull();
    expect(card('Kit').querySelector('.persona-desc')?.textContent).toBe('No description');
  });

  it('served avatars load from the avatar route; the rest get the person glyph', async () => {
    await render();
    expect(card('Ada').querySelector('.persona-av img')?.getAttribute('src'))
      .toBe('/api/personas/p1/avatar');
    expect(card('Kit').querySelector('.persona-av img')).toBeNull();
    expect(card('Kit').querySelector('.persona-av svg')).toBeTruthy();
  });

  it('tapping another card and its Make default chip both set the default', async () => {
    post.mockResolvedValue({ personas });
    await render();
    await act(async () => {
      card('Kit').click();
      await Promise.resolve();
    });
    expect(post).toHaveBeenCalledWith('/api/personas/select', { id: 'p2' });
    post.mockClear();
    await act(async () => {
      card('Kit').querySelector<HTMLButtonElement>('.persona-make')!.click();
      await Promise.resolve();
    });
    expect(post).toHaveBeenCalledWith('/api/personas/select', { id: 'p2' });
  });

  it('Delete is offered only while more than one persona exists', async () => {
    await render();
    await act(async () => {
      card('Kit')
        .querySelector<HTMLButtonElement>('button[aria-label="More actions for Kit"]')!
        .click();
    });
    expect([...host.querySelectorAll('.card-menu-item')].some((b) => b.textContent?.includes('Delete')))
      .toBe(true);
    // Remount with one persona: the desktop hides Delete at the last card.
    get.mockResolvedValue({ personas: [personas[0]] });
    act(() => root.unmount());
    root = createRoot(host);
    await render();
    await act(async () => {
      host
        .querySelector<HTMLButtonElement>('button[aria-label="More actions for Ada"]')!
        .click();
    });
    expect([...host.querySelectorAll('.card-menu-item')].some((b) => b.textContent?.includes('Delete')))
      .toBe(false);
  });

  it('the kebab keeps the accessible names the specs drive it with', async () => {
    await render();
    await act(async () => {
      card('Ada')
        .querySelector<HTMLButtonElement>('button[aria-label="More actions for Ada"]')!
        .click();
    });
    expect(host.querySelector('[aria-label="Export Ada as JSON"]')).toBeTruthy();
    expect(host.querySelector('[aria-label="Make a character from Ada"]')).toBeTruthy();
  });

  it('a menu item on a non-default card does not ride the card tap into set-default', async () => {
    // The desktop's PopupMenuButton claims its taps; a menu click here must
    // not fire select() on the way out of the card (it silently moved the
    // default, and raced Delete against a select of a doomed id).
    post.mockResolvedValue({ personas });
    get.mockImplementation(async (path: string) =>
      path === '/api/personas/p2/detail'
        ? { id: 'p2', title: '', name: 'Kit', persona: 'text', birthday: '' }
        : { personas });
    await render();
    await act(async () => {
      card('Kit')
        .querySelector<HTMLButtonElement>('button[aria-label="More actions for Kit"]')!
        .click();
    });
    await act(async () => {
      host
        .querySelector<HTMLButtonElement>('button[aria-label="Edit Kit"]')!
        .click();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(post.mock.calls.some((c) => c[0] === '/api/personas/select')).toBe(false);
    // And the edit actually opened.
    expect(host.querySelector('.persona-edit')).toBeTruthy();
  });
});
