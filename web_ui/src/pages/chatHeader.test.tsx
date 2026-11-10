// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat header is the desktop window's at every width (PR 1a wide, PR 1b
// phone and tablet): Back, the cast stack or portrait, the name with its
// group line, and one sidebar button. The phone's old Stats / Conversations /
// model chip / ⋯ row is gone — those controls live in the composer row and
// the sidebar. Below 1024 the sidebar button opens the drawer: full screen on
// a phone, a slide-over on a tablet. Pinned through the real ChatPage.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter, Route, Routes, useParams } from 'react-router-dom';
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
const toggle = () =>
  header().querySelector<HTMLButtonElement>('button[aria-label="Toggle sidebar"]')!;
const menuItems = () =>
  [...document.querySelectorAll('[role="menu"] [role="menuitem"]')] as HTMLButtonElement[];

function tap(el: Element | null | undefined) {
  if (!el) throw new Error('nothing to tap');
  act(() => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

function openSidebar() {
  tap(toggle());
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  (Element.prototype as unknown as { scrollTo: () => void }).scrollTo = () => {};
  localStorage.clear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('phone chat header', () => {
  it('is Back, the name and the sidebar button — nothing else', async () => {
    await render(390);
    expect(header().querySelector('button[aria-label="Back"]')).not.toBeNull();
    expect(header().querySelector('button[aria-label="Toggle sidebar"]')).not.toBeNull();
    expect(header().textContent).toContain('Ann');
    // The old phone row: model chip, Stats, Conversations, ⋯.
    expect(header().querySelector('button[aria-haspopup="menu"]')).toBeNull();
    expect(header().textContent).not.toContain('Stats');
    expect(header().textContent).not.toContain('Conversations');
    expect(header().querySelector('.model-switch-chip')).toBeNull();
    expect(headerButtons()).not.toContain('⋯');
  });

  it('the sidebar button opens ChatSidebar full screen, and Close hides it', async () => {
    await render(390);
    expect(container.querySelector('.chat-sidebar-drawer')).toBeNull();

    openSidebar();
    const drawer = container.querySelector('.chat-sidebar-drawer')!;
    expect(drawer).not.toBeNull();
    expect(drawer.className).toContain('full');
    // The same card tree as wide, not the old flat panel.
    expect(drawer.querySelector('.chat-sidebar')).not.toBeNull();
    expect(drawer.textContent).toContain('Main Settings');
    expect(drawer.textContent).toContain('Reset to default');
    expect(container.querySelector('.chat-sidebar-backdrop')?.getAttribute('aria-hidden')).toBeNull();

    const close = drawer.querySelector('button[aria-label="Close"]');
    expect(close).not.toBeNull();
    tap(close);
    expect(container.querySelector('.chat-sidebar-backdrop')?.getAttribute('aria-hidden')).toBe('true');

    // Reopening keeps the card tree's scroll position.
    const body = drawer.querySelector('.chat-sidebar-drawer-body') as HTMLElement;
    body.scrollTop = 140;
    openSidebar();
    expect(container.querySelector('.chat-sidebar-drawer-body')).toBe(body);
    expect((container.querySelector('.chat-sidebar-drawer-body') as HTMLElement).scrollTop).toBe(140);
  });

  it('the group header stacks the cast and carries the group line', async () => {
    const before = { ...chatState };
    Object.assign(chatState, {
      isGroupMode: true,
      groupId: 'g1',
      character: { name: 'Mara', id: 'lib-mara' },
      cast: [
        { id: 'm1', dbId: 'm1', name: 'Mara', isHost: true, realismEnabled: true },
        { id: 'm2', dbId: 'm2', name: 'Dez', isHost: false, realismEnabled: true },
        { id: 'm3', dbId: 'm3', name: 'Hollis', isHost: false, realismEnabled: true },
      ],
    });
    try {
      await render(390);
      expect(header().querySelectorAll('.chat-stack-avatar')).toHaveLength(3);
      expect(header().textContent).toContain('3 characters');
    } finally {
      for (const k of Object.keys(chatState)) delete (chatState as Record<string, unknown>)[k];
      Object.assign(chatState, before);
    }
  });
});

describe('tablet chat header', () => {
  it('the sidebar button slides the panel over; a tap on the dimmed chat hides it', async () => {
    await render(820);
    expect(container.querySelector('.chat-sidebar-drawer')).toBeNull();

    openSidebar();
    const backdrop = container.querySelector('.chat-sidebar-backdrop')!;
    expect(backdrop).not.toBeNull();
    expect(backdrop.className).toContain('slide');
    expect(container.querySelector('.chat-sidebar-drawer')?.className).toContain('slide');
    expect(backdrop.getAttribute('aria-hidden')).toBeNull();

    // The dimmed chat is the backdrop itself.
    tap(backdrop);
    expect(backdrop.getAttribute('aria-hidden')).toBe('true');
  });
});

describe('wide chat header', () => {
  it('the sidebar button shows and hides the column', async () => {
    await render(1280);
    expect(container.querySelector('.chat-aside')).not.toBeNull();
    openSidebar();
    expect(container.querySelector('.chat-aside')).toBeNull();
    openSidebar();
    expect(container.querySelector('.chat-aside')).not.toBeNull();
  });

  it('keeps every control reachable and has no ⋯', async () => {
    await render(1280);
    expect(header().querySelector('button[aria-haspopup="menu"]')).toBeNull();
    // Persona sits in the composer icon row, Conversations ▾ behind the
    // folder, and Chat settings behind Main Settings.
    expect(
      container.querySelector('.composer-icon-row button[aria-label="Persona"]'),
    ).not.toBeNull();
    tap(container.querySelector('.chat-mgmt-btn'));
    expect(menuItems().some((b) => b.textContent?.includes('Conversations ▾'))).toBe(true);
    tap(container.querySelector('.chat-mgmt-btn')); // close the folder
    tap(container.querySelector('.sidebar-main-settings'));
    tap(menuItems().find((b) => b.textContent?.includes('Chat Settings')));
    expect(container.querySelector('.settings-drawer')?.textContent).toContain('Chat theme');
  });
});

// In a group, Edit opens the focused member's editor: the group's own copy
// of the character, never the library card (that route had no Edit at all).
function MemberEditorStandIn() {
  const { groupId, memberId } = useParams();
  return createElement('div', { className: 'member-editor-stand-in' }, `${groupId}/${memberId}`);
}

describe('chat header in a group', () => {
  it("Edit character opens the focused member's editor", async () => {
    const before = { ...chatState };
    Object.assign(chatState, {
      isGroupMode: true,
      groupId: 'g1',
      character: { name: 'Mara', id: 'lib-mara' },
      cast: [{ id: 'm1', dbId: 'mem-mara', name: 'Mara', isHost: false, realismEnabled: true }],
    });
    try {
      (window as { innerWidth: number }).innerWidth = 1280;
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
                path: '/groups/:groupId/members/:memberId/edit',
                element: createElement(MemberEditorStandIn),
              }),
            ),
          ),
        );
      });
      await act(async () => {
        await Promise.resolve();
      });
      // Edit lives behind the sidebar's Main Settings menu; the editor it
      // opens is the check that stays.
      tap(container.querySelector('.sidebar-main-settings'));
      tap(menuItems().find((b) => b.textContent?.includes('Edit Character')));
      expect(container.querySelector('.member-editor-stand-in')?.textContent).toBe('g1/mem-mara');
    } finally {
      for (const k of Object.keys(chatState)) delete (chatState as Record<string, unknown>)[k];
      Object.assign(chatState, before);
    }
  });
});
