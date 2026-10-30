// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's twin of the desktop Members rows' voice pickers: no pick keeps
// the card's own voice, '' is the global voice, anything else is the voice.
// Desktop twin: test/ui/pages/create_group_after_restore_test.dart.

import { act, createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

let voices: { id: string; name: string; gender?: string }[] = [];
vi.mock('../../api/client', () => ({
  api: { get: async () => ({ globalVoice: 'af_sky', voices }) },
}));

const { MemberVoicePicks } = await import('./MemberVoicePicks');

let container: HTMLDivElement;
let root: Root;
let latest: Record<string, string> = {};

function Harness() {
  const [picks, setPicks] = useState<Record<string, string>>({});
  latest = picks;
  return createElement(MemberVoicePicks, {
    members: [
      { id: 'j', name: 'Juniper' },
      { id: 'm', name: 'Marlow' },
    ],
    voices: picks,
    set: setPicks,
  });
}

async function mount() {
  await act(async () => {
    root.render(createElement(Harness));
  });
}

function select(name: string): HTMLSelectElement {
  return container.querySelector(`select[aria-label="${name}'s voice"]`)!;
}

function choose(name: string, value: string) {
  const s = select(name);
  act(() => {
    s.value = value;
    s.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  latest = {};
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('picks a voice, the global voice, and back to the card own voice', async () => {
  voices = [
    { id: 'af_sky', name: 'Sky', gender: 'Female' },
    { id: 'am_adam', name: 'Adam', gender: 'Male' },
  ];
  await mount();
  expect(select('Juniper').value, 'no pick shows the card own voice').toBe('__own__');

  choose('Juniper', 'am_adam');
  choose('Marlow', '');
  expect(latest).toEqual({ j: 'am_adam', m: '' });
  expect(select('Marlow').selectedOptions[0].textContent).toBe('Use the global voice (Sky)');

  choose('Juniper', '__own__');
  expect(latest, 'Their own voice drops the pick').toEqual({ m: '' });
});

it('says how to get voices while text-to-speech has none', async () => {
  voices = [];
  await mount();
  expect(container.querySelector('select')).toBeNull();
  expect(container.textContent).toContain('Enable text-to-speech on the desktop app');
});
