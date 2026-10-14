// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web creator's page around the Profile step. A reload that cannot
// reach the relay says so with Try again (and stops saying "Loading"); Try
// again brings the waiting profile back. A second Generate drops the old
// profile, so a failed second run cannot go Next onto the first. Stop
// while the rest is written goes back to the Profile step. (Its own file:
// the Greetings page test's relay stand-in has no profile answers.)

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { WsEvent } from '../api/ws';

const listeners: ((e: WsEvent) => void)[] = [];
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: (e: WsEvent) => void) {
      listeners.push(cb);
    }
    connect() {}
    close() {}
  },
}));

const VIEW = {
  name: 'Aria Vale',
  description: '{{char}} keeps the light.',
  personality: 'Dry.',
  scenario: 'A storm.',
  facts: { occupation: 'keeper' },
  mode: 'quick',
};
let profileFails = false;
const posts: string[] = [];
vi.mock('../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path === '/api/chargen/status') return { available: true };
      if (path.startsWith('/api/chargen/profile')) {
        if (profileFails) throw new Error('offline');
        return { pending: VIEW, creating: false };
      }
      return {};
    },
    post: async (path: string) => {
      posts.push(path);
      return path.endsWith('/stop') ? { stopped: true } : { status: 'started' };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { CreateAiCharacterPage } = await import('./CreateAiCharacterPage');

let container: HTMLDivElement;
let root: Root;

function render(entry: string) {
  act(() => {
    root.render(
      createElement(
        MemoryRouter,
        { initialEntries: [entry] },
        createElement(
          Routes,
          null,
          createElement(Route, { path: '/create-ai', element: createElement(CreateAiCharacterPage) }),
        ),
      ),
    );
  });
}

async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}

const buttonNamed = (text: RegExp) =>
  Array.from(container.querySelectorAll('button')).find((b) => text.test(b.textContent ?? ''))!;

function emit(e: WsEvent) {
  act(() => {
    for (const l of listeners) l(e);
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  listeners.length = 0;
  posts.length = 0;
  profileFails = false;
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('the first pass shows the same screen with no Stop (the relay cannot stop a create)', async () => {
  render('/create-ai');
  await settle();
  const name = container.querySelector('.cg-field input') as HTMLInputElement;
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(name, 'Aria Vale');
  act(() => {
    name.dispatchEvent(new Event('input', { bubbles: true }));
  });
  for (const label of [/^Next: Details/, /^Next: Output/, /^Next: Generate/]) {
    await act(async () => {
      buttonNamed(label).click();
    });
  }
  await act(async () => {
    buttonNamed(/Generate character/).click();
  });
  const panel = container.querySelector('[data-testid="generating-panel"]')!;
  expect(panel).not.toBeNull();
  expect(panel.querySelectorAll('button')).toHaveLength(0);
});

it('a reload that cannot reach the relay says so, and Try again brings the profile back', async () => {
  profileFails = true;
  render('/create-ai?profile=pending');
  await settle();
  expect(container.textContent).toContain('The profile could not be loaded.');
  expect(container.textContent).not.toContain('Loading the profile');
  profileFails = false;
  await act(async () => {
    buttonNamed(/Try again/).click();
  });
  await settle();
  expect(container.querySelector('[data-testid="profile-step"]')).not.toBeNull();
});

it('a second Generate drops the profile the first one left', async () => {
  render('/create-ai');
  await settle();
  const name = container.querySelector('.cg-field input') as HTMLInputElement;
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(name, 'Aria Vale');
  act(() => {
    name.dispatchEvent(new Event('input', { bubbles: true }));
  });
  emit({ event: 'chargen_profile', ...VIEW } as WsEvent);
  expect(container.querySelector('[data-testid="profile-step"]')).not.toBeNull();
  await act(async () => {
    buttonNamed(/^Back/).click();
  });
  await act(async () => {
    buttonNamed(/Generate character/).click();
  });
  emit({ event: 'chargen_error', error: 'no model' });
  expect(container.textContent).toContain('no model');
  expect(buttonNamed(/^Next: Profile/).disabled).toBe(true);
});

it('Stop while the rest is written goes back to the profile', async () => {
  render('/create-ai');
  await settle();
  emit({ event: 'chargen_profile', ...VIEW } as WsEvent);
  await act(async () => {
    buttonNamed(/^Next: Greetings/).click();
  });
  // The Generate screen again: the status, the bar, and one button, Stop,
  // in the panel (no disabled "Generating…" button beside it).
  const panel = container.querySelector('[data-testid="generating-panel"]')!;
  expect(panel.textContent).toContain('Generating…');
  expect(panel.querySelector('[role="progressbar"]')).not.toBeNull();
  expect(Array.from(panel.querySelectorAll('button')).map((b) => b.textContent)).toEqual(['Stop']);
  expect(buttonNamed(/Generating…|Generate character/)).toBeUndefined();
  emit({ event: 'chargen_status', data: 'Writing first message...' });
  expect(panel.querySelector('.cg-gen-status')?.textContent).toBe('Writing first message...');
  await act(async () => {
    buttonNamed(/^Stop$/).click();
  });
  expect(posts).toContain('/api/chargen/profile/stop');
  emit({ event: 'chargen_profile_stopped', phase: 'complete' });
  expect(container.querySelector('[data-testid="profile-step"]')).not.toBeNull();
  expect(buttonNamed(/^Next: Greetings/).disabled).toBe(false);
});
