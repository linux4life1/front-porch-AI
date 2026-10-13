// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Make a Character" from a persona: the phone wizards show the persona's
// picture, as the desktop wizard does, before the card is saved.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

vi.mock('../../api/client', () => ({ api: { get: vi.fn() } }));

const { PersonaSeedNote } = await import('./PersonaConvertDialogs');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const seed = { personaId: 'p 1', name: 'Jo', description: '', birthday: '', aiConcept: '' };

it("shows the persona's picture from the relay when it has one", () => {
  act(() => root.render(createElement(PersonaSeedNote, { seed: { ...seed, hasPortrait: true } })));
  const pic = container.querySelector<HTMLImageElement>('[data-testid="persona-seed-portrait"]');
  expect(pic?.getAttribute('src')).toBe('/api/persona-convert/persona/p%201/portrait');
  expect(container.textContent).toContain('its picture becomes the portrait');
});

it('shows no picture for a persona without one', () => {
  act(() => root.render(createElement(PersonaSeedNote, { seed: { ...seed, hasPortrait: false } })));
  expect(container.querySelector('img')).toBeNull();
});
