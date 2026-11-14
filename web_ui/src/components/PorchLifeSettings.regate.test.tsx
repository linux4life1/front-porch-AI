// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// After Dark re-gates live. The 18+ master switch moved to General
// (AdultThemesCard, PR 7a); when it writes `realism.adultThemesEnabled`
// off, the Porch Life card must hide its After Dark group at once —
// the switch's own copy says "Off means they are simply not there".
// A page reload may not be the mechanism: the card re-reads on the
// `settings_changed` broadcast. Guard: prove red by dropping the socket
// listener in PorchLifeSettings.tsx.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

type Listener = (e: { event: string }) => void;
let listener: Listener | null = null;
let adultOn = true;

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: Listener) {
      listener = cb;
    }
    connect() {}
    close() {
      listener = null;
    }
  },
}));

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => Promise.resolve({ realism: { adultThemesEnabled: adultOn } }),
    post: () => Promise.resolve({}),
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  adultOn = true;
  listener = null;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
});

const afterDark = () =>
  [...host.querySelectorAll('.pl-group-title')].some((t) =>
    (t.textContent ?? '').includes('After Dark'),
  );

it('shows After Dark while the master switch is on', async () => {
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
  expect(afterDark()).toBe(true);
});

it('hides After Dark when another surface flips 18+ off, without a reload', async () => {
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
  expect(afterDark()).toBe(true);

  adultOn = false; // General's AdultThemesCard wrote the key…
  await act(async () => {
    listener?.({ event: 'settings_changed' }); // …and the host broadcast it.
    await Promise.resolve();
  });
  expect(afterDark()).toBe(false);
});
