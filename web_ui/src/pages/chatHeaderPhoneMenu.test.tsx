// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone chat header keeps one line: Stats, Conversations and a ⋯ menu
// holding Edit, Persona and Theme. Pinned through the real ChatPage, so each
// menu item must reach the same drawer / page its wide-screen button opens.
// Red proof: with the phone branch removed from ChatHeader (every width gets
// the wide row) the phone cases fail: there is no ⋯ to open.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => {
      if (path === '/api/chat/state') return Promise.resolve(chatState);
      return new Promise(() => {});
    },
    post: () => Promise.resolve({}),
    upload: () => new Promise(() => {}),
  },
  ApiError: class ApiError extends Error {},
}));

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const auth = { setAuthenticated: () => {} };
vi.mock('../auth/AuthContext', () => ({ useAuth: () => auth }));

const chatState = {
  character: { name: 'Ann', id: 'c1' },
  sessionId: 's1',
  messages: [],
  isGenerating: false,
  cast: [{ id: 'c1', dbId: 'c1', name: 'Ann', isHost: true, realismEnabled: true }],
  realism: {
    realismEnabled: true,
    bond: { score: 0, tier: 'Acquaintance', percent: 0 },
    longTerm: { score: 0, tier: 'Acquaintance', percent: 0 },
    trust: { level: 0, tier: 'Wary', percent: 0 },
    emotion: 'neutral',
    emotionIntensity: 'mild',
    mood: 'neutral',
    arousal: { level: 0, tier: 'calm' },
    fixation: '',
    needsEnabled: false,
    needs: {},
  },
};

const { ChatPage } = await import('./ChatPage');

let container: HTMLDivElement;
let root: Root;

async function render(width: number) {
  (window as { innerWidth: number }).innerWidth = width;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      createElement(
        MemoryRouter,
        { initialEntries: ['/chat'] },
        createElement(
          Routes,
          null,
          createElement(Route, { path: '/chat', element: createElement(ChatPage) }),
          createElement(Route, {
            path: '/edit/:id',
            element: createElement('div', { className: 'edit-page-stand-in' }),
          }),
        ),
      ),
    );
  });
  await act(async () => {
    await Promise.resolve();
  });
}

const header = () => container.querySelector('.chat-header') as HTMLElement;
const headerButtons = () =>
  [...header().querySelectorAll('button')].map((b) => b.textContent?.trim());
const menuItems = () =>
  [...document.querySelectorAll('[role="menu"] [role="menuitem"]')] as HTMLButtonElement[];

function tap(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to tap');
  act(() => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

function openMore() {
  tap(header().querySelector('button[aria-haspopup="menu"]'));
}

function choose(label: string) {
  tap(menuItems().find((b) => b.textContent?.includes(label)));
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  (Element.prototype as unknown as { scrollTo: () => void }).scrollTo = () => {};
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('phone chat header', () => {
  it('shows Stats, Conversations and ⋯, with Edit, Persona and Theme in the menu', async () => {
    await render(390);
    const more = header().querySelector('button[aria-haspopup="menu"]');
    expect(more?.getAttribute('aria-label')).toBe('More chat options');
    expect(more?.getAttribute('aria-expanded')).toBe('false');
    expect(headerButtons()).toEqual(expect.arrayContaining(['Stats ▾', 'Conversations ▾']));
    expect(headerButtons()).not.toContain('Persona');
    expect(headerButtons()).not.toContain('Theme');
    expect(headerButtons()).not.toContain('✎');

    openMore();
    expect(more?.getAttribute('aria-expanded')).toBe('true');
    expect(menuItems().map((b) => b.textContent)).toEqual(['✎Edit character', '👤Persona', '🎨Theme']);
    expect(document.activeElement).toBe(menuItems()[0]);
  });

  it('Theme opens the chat theme drawer and closes the menu', async () => {
    await render(390);
    openMore();
    choose('Theme');
    expect(menuItems()).toHaveLength(0);
    expect(container.querySelector('.settings-drawer')?.textContent).toContain('Chat theme');
  });

  it('Persona opens the speak-as picker', async () => {
    await render(390);
    openMore();
    choose('Persona');
    expect(container.querySelector('.modal')?.textContent).toContain('Speak as…');
  });

  it('Edit character goes to the character editor', async () => {
    await render(390);
    openMore();
    choose('Edit character');
    expect(container.querySelector('.edit-page-stand-in')).not.toBeNull();
  });

  it('closes on Escape and on a tap outside, opening nothing', async () => {
    await render(390);
    openMore();
    act(() => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    });
    expect(menuItems()).toHaveLength(0);

    openMore();
    tap(document.querySelector('.card-menu-backdrop'));
    expect(menuItems()).toHaveLength(0);
    expect(container.querySelector('.settings-drawer')).toBeNull();
    expect(container.querySelector('.modal')).toBeNull();
  });
});

describe('wide chat header', () => {
  it('keeps every button in the row and has no ⋯', async () => {
    await render(1280);
    expect(header().querySelector('button[aria-haspopup="menu"]')).toBeNull();
    expect(headerButtons()).toEqual(expect.arrayContaining(['✎', 'Persona', 'Theme', 'Conversations ▾']));
    tap([...header().querySelectorAll('button')].find((b) => b.textContent === 'Theme'));
    expect(container.querySelector('.settings-drawer')?.textContent).toContain('Chat theme');
  });
});
