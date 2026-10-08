// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, expect, it, vi } from 'vitest';
import { act } from 'react';
import {
  button, click, container, createElement, mount, pickOption, posts, refuse, reset,
  serve, settle, unmount, until,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);
const { PackPanel } = await import('./PackPanel');
const rules = { prefix: 'local wording', suffix: '', replacements: [] };
const view = (origin = 'phone') => ({
  origin, running: false, mode: 'edit', characterId: 'c1', characterName: 'Review character',
  total: 1, done: 0, kept: 0, canImport: false, imported: null, slots: [], promptRules: rules,
});

Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
  configurable: true, value() { this.setAttribute('open', ''); },
});
Object.defineProperty(HTMLDialogElement.prototype, 'close', {
  configurable: true, value() { this.removeAttribute('open'); },
});
afterEach(() => { unmount(); reset(); window.localStorage.clear(); });

it('uses local wording once, then lets the next pack use global defaults', async () => {
  serve({
    'GET /api/characters': [{ id: 'c1', name: 'Review character' }],
    'GET /api/image/expression-pack': refuse(404, 'No pack'),
    'GET /api/image/expression-pack/source': { image: 'data:image/png;base64,AAAA' },
    'GET /api/image/expression-pack/settings': rules,
    'POST /api/image/expression-pack/preview': { previews: [] },
    'POST /api/image/expression-pack': view(),
    'POST /api/image/expression-pack/discard': {},
  });
  mount(createElement(PackPanel, { initialPrompt: 'portrait', initialPicture: null }));
  await settle();
  // The workspace picks no target on its own; the pack is built from the
  // card's portrait once a character is chosen.
  pickOption('select[aria-label="Character"]', 'c1');
  await until(() => !button('Start pack')!.disabled);
  click('Prompt rules...');
  await until(() => !!container.querySelector('dialog'));
  await until(() => !button('Use for this pack')!.disabled);
  click('Use for this pack');
  await settle();
  click('Start pack');
  await settle();
  expect(posts('/api/image/expression-pack')[0].body).toHaveProperty('promptRules', rules);
  // A started pack holds its target; Reset pack discards it before another start.
  click('Reset pack');
  await until(() => [...container.querySelectorAll('button')].filter((b) => b.textContent === 'Reset pack').length === 2);
  act(() => { [...container.querySelectorAll('button')].filter((b) => b.textContent === 'Reset pack').at(-1)!.click(); });
  await until(() => !button('Start pack')!.disabled);
  click('Start pack');
  await settle();
  expect(posts('/api/image/expression-pack')[1].body).not.toHaveProperty('promptRules');
});

it('does not offer rule editing or continuation for a desktop-owned pack', async () => {
  serve({
    'GET /api/characters': [{ id: 'c1', name: 'Review character' }],
    'GET /api/image/expression-pack': view('desktop'),
  });
  mount(createElement(PackPanel, { initialPrompt: 'portrait', initialPicture: null }));
  await settle();
  expect(container.textContent).toContain('Started on the computer.');
  expect(button('Edit pack prompt rules...')).toBeUndefined();
  expect(button('Generate remaining')).toBeUndefined();
});
