// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { MessageContent } from './MessageContent';
import { ScenarioCardTypeField } from './ScenarioCardTypeField';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.append(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

test('explicitly selects Scenario and preserves an unsupported type in the editor', () => {
  const change = vi.fn();
  act(() => root.render(<ScenarioCardTypeField value="character" onChange={change} />));
  const selector = container.querySelector('select')!;
  expect(selector.value).toBe('character');
  act(() => {
    selector.value = 'scenario';
    selector.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(change).toHaveBeenCalledWith('scenario');
  act(() => root.render(<ScenarioCardTypeField value="unsupported" onChange={change} />));
  expect(selector.disabled).toBe(true);
  expect(selector.value).toBe('unsupported');
});

test('the Scenario transcript keeps incidental dialogue and prose punctuation', () => {
  const body = 'Keeper: "You can take the stairs."\n*Wind rattles the shutter.*';
  act(() => root.render(<MessageContent text={body} plainProse />));
  expect(container.textContent).toBe(body);
  expect(container.querySelector('em')).toBeNull();
});
