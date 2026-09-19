// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// P0 #3 web HOLD: Journal off hides Recap Edit / Regenerate (desktop hide).

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ToolsState } from './ChatToolsShared';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));

vi.mock('../api/client', () => ({
  api: { post: (url: string, body?: unknown) => post(url, body) },
}));

const { ChatToolsRecap } = await import('./ChatToolsMemory');

let container: HTMLDivElement;
let root: Root;

function recapState(journalEnabled: boolean): ToolsState {
  return {
    realismEnabled: true,
    needsEnabled: true,
    realismOneShotEval: false,
    memory: {
      ragEnabled: false,
      ragRetrievalCount: 3,
      ragWindowSize: 5,
      journalEnabled,
      journalInterval: 10,
      growthEnabled: false,
      growthInterval: 10,
      growthReviewFirst: false,
    },
    summary: {
      text: 'They met on the porch.',
      paused: false,
      isGenerating: false,
      lastIndex: 4,
    },
    chaos: {
      enabled: false,
      nsfwEnabled: false,
      pressure: 0,
      hasPendingEvent: false,
    },
    nsfw: {
      cooldownEnabled: false,
      cooldownTurnsRemaining: 0,
      arousalLevel: 0,
      arousalTier: '',
    },
    time: {
      weekday: 'Tuesday',
      dayCount: 3,
      timeOfDay: 'evening',
      passageEnabled: true,
    },
    objectives: {
      primary: null,
      secondary: [],
      isChecking: false,
    },
  };
}

function render(journalEnabled: boolean) {
  act(() => {
    root.render(
      createElement(ChatToolsRecap, {
        t: recapState(journalEnabled),
        q: '',
        apply: (p) => {
          void p;
        },
        toggle: () => {},
        reloadKey: 0,
      }),
    );
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
    true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockClear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ChatToolsRecap journal gate', () => {
  it('hides Edit and Regenerate when Journal is off', () => {
    render(false);
    const labels = [...container.querySelectorAll('button')].map(
      (b) => b.textContent?.trim(),
    );
    expect(labels).not.toContain('Edit');
    expect(labels).not.toContain('Regenerate');
    expect(container.textContent).toMatch(/Journal is off|recap are paused/i);
    expect(post).not.toHaveBeenCalled();
  });

  it('shows Edit and Regenerate when Journal is on', () => {
    render(true);
    const labels = [...container.querySelectorAll('button')].map(
      (b) => b.textContent?.trim(),
    );
    expect(labels).toContain('Edit');
    expect(labels).toContain('Regenerate');
  });

  it('ChatTools only mounts Recap when Journal is on', () => {
    const src = readFileSync(join(__dirname, 'ChatTools.tsx'), 'utf8');
    expect(src).toContain('t.memory.journalEnabled');
    const recap = src.indexOf('<ChatToolsRecap');
    expect(recap, 'ChatToolsRecap mount').toBeGreaterThanOrEqual(0);
    const gate = src.lastIndexOf('journalEnabled', recap);
    expect(gate, 'mount is gated on journalEnabled').toBeGreaterThan(
      src.indexOf('return ('),
    );
    expect(gate).toBeLessThan(recap);
  });
});
