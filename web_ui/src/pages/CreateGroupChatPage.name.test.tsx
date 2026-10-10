// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's New Group names the group after every member until the user
// types a name, and follows the roster when it changes; a typed name stays.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const CHARS = ['Juniper', 'Marlow', 'Ivy', 'Rowan'].map((name) => ({
  id: name.toLowerCase(),
  name,
  hasAvatar: false,
  folderId: '',
}));

vi.mock('../api/client', () => ({
  api: {
    get: async (path: string) => (path.startsWith('/api/folders') ? { folders: [] } : CHARS),
    post: async () => ({}),
    avatarUrl: () => '',
  },
  ApiError: class ApiError extends Error {},
}));

const { CreateGroupChatPage } = await import('./CreateGroupChatPage');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(CreateGroupChatPage)));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function button(label: string): HTMLButtonElement {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent?.includes(label));
  if (!b) throw new Error(`no button "${label}"`);
  return b;
}

const click = (label: string) => act(() => button(label).click());

function nameBox(): HTMLInputElement {
  const box = container.querySelector<HTMLInputElement>('input[placeholder="Name this group"]');
  if (!box) throw new Error('no Group name box');
  return box;
}

function type(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

it('follows the roster until a name is typed', () => {
  click('Juniper');
  click('Marlow');
  click('Next');
  expect(nameBox().value).toBe('Juniper & Marlow');

  click('Back');
  click('Ivy');
  click('Next');
  expect(nameBox().value).toBe('Juniper, Marlow & Ivy');

  click('Back');
  click('Rowan');
  click('Next');
  expect(nameBox().value).toBe('Juniper & 3 others');

  type(nameBox(), 'Porch Regulars');
  click('Back');
  click('Rowan');
  click('Next');
  expect(nameBox().value).toBe('Porch Regulars');
});
