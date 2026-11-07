// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Past five steps the indicator marks itself `many`, so wizard.css can keep
// only the current label on a phone (the seven-step group wizard collided at
// 375 px). Short wizards keep every label.

import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it } from 'vitest';

import { StepIndicator } from './StepIndicator';

function render(steps: string[]) {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  const el = document.createElement('div');
  const root = createRoot(el);
  act(() => root.render(createElement(StepIndicator, { steps, current: 0 })));
  const cls = el.firstElementChild?.className ?? '';
  act(() => root.unmount());
  return cls;
}

it('a seven-step wizard is marked many; a five-step one is not', () => {
  expect(render(['a', 'b', 'c', 'd', 'e', 'f', 'g']).split(' ')).toContain('many');
  expect(render(['a', 'b', 'c', 'd', 'e']).split(' ')).not.toContain('many');
});
