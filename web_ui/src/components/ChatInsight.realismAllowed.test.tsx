// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The insight panel's "Realism off" line names Porch Life when Porch Life is
// what stops Realism, as the desktop's Character State does; an older
// desktop sends no realismAllowed and keeps today's line.
// Relay twin: lib/services/web/facade/chat_realism_read.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');

const base: Realism = {
  realismEnabled: false,
  bond: { score: 0, tier: 'Neutral', percent: 0.5 },
  longTerm: { score: 0, tier: 'Neutral', percent: 0.5 },
  trust: { level: 0, tier: 'None', percent: 0.5 },
  emotion: 'calm',
  emotionIntensity: 'mild',
  mood: 'calm',
  arousal: { level: 0, tier: 'None' },
  fixation: '',
  needsEnabled: false,
  needs: {},
};

let container: HTMLDivElement;
let root: Root;

function render(realism: Realism) {
  act(() => {
    root.render(
      createElement(ChatInsight, {
        realism,
        lorebook: [],
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: false,
        focusedIsHost: true,
        toolsKey: 0,
        focusedId: null,
        onCommand: () => {},
      }),
    );
  });
}

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

it('names Porch Life while it blocks Realism', () => {
  render({ ...base, realismAllowed: false });
  const line = container.querySelector('.realism-off')!.textContent;
  expect(line).toContain('The Realism Engine is off in Porch Life');
  expect(line).not.toContain('flip the switch');
});

it("keeps today's line when the chat's own switch is what is off", () => {
  render(base);
  const line = container.querySelector('.realism-off')!.textContent;
  expect(line).toContain('flip the switch');
});

it('allowed again mid-reply, with its own switch on: says Realism starts again when the reply finishes', () => {
  render({ ...base, realismAllowed: true, realismSwitch: true });
  const line = container.querySelector('.realism-off')!.textContent;
  expect(line).toContain('Realism starts again when this reply finishes.');
  expect(line).not.toContain('flip the switch');
});
