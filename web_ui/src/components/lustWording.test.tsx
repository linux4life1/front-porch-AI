// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone names the desire stat the way the desktop does: "Lust" (desktop
// bond_bars.dart and group_member_card_views.dart label the bar 'Lust'; the
// reply chip reads 'Lust: +N' in message_bubble.realism.dart). The wire keys
// stay arousal*. Red proof: putting "Arousal" back in any of the three
// components fails its case.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';
import type { ToolsState } from './ChatToolsShared';

// The insight panel's own requests never settle; nothing they load is pinned.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');
const { ChatToolsNsfw } = await import('./ChatToolsRealism');
const { ChipsRow } = await import('./ChipsRow');

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

function statLineLabels(): string[] {
  return [...container.querySelectorAll('.stat-line > span:first-child')].map(
    (s) => s.textContent ?? '',
  );
}

describe('the desire stat is called Lust on the phone', () => {
  it('in the Stats panel', () => {
    const realism: Realism = {
      realismEnabled: true,
      bond: { score: 12, tier: 'Friendly', percent: 0.52 },
      longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
      trust: { level: 8, tier: 'Some', percent: 0.54 },
      emotion: 'calm',
      emotionIntensity: 'mild',
      mood: 'calm',
      arousal: { level: 7, tier: 'Warm' },
      fixation: '',
    };
    act(() => {
      root.render(
        createElement(ChatInsight, {
          realism,
          authorNote: '',
          authorNoteDepth: 4,
          onSaveAuthorNote: () => {},
          characterId: 'c1',
          isGroup: false,
          focusedIsHost: true,
          toolsKey: 0,
          focusedId: null,
          groupId: null,
          onCommand: () => {},
        }),
      );
    });
    expect(statLineLabels()).toContain('Lust');
    expect(container.textContent).not.toContain('Arousal');
  });

  it('in the chat tools NSFW section', () => {
    const t = {
      nsfw: {
        cooldownEnabled: true,
        refractoryMinutesRemaining: 0,
        refractoryClockRunning: true,
        refractoryLabel: '',
        arousalLevel: 7,
        arousalTier: 'Warm',
      },
    } as ToolsState;
    act(() => {
      root.render(createElement(ChatToolsNsfw, { t, toggle: () => {} }));
    });
    expect(statLineLabels()).toContain('Lust');
    expect(container.textContent).not.toContain('Arousal');
  });

  it('on a reply chip', () => {
    act(() => {
      root.render(
        createElement(ChipsRow, {
          chips: { arousalDelta: 3 },
          isLast: false,
          busy: false,
          onReprocess: vi.fn(),
          onRevert: vi.fn(),
        }),
      );
    });
    expect(container.textContent).toContain('Lust +3');
    expect(container.textContent).not.toContain('Arousal');
  });
});
