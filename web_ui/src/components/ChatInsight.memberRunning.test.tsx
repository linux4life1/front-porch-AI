// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's view of a focused group member shows what runs for that
// member, as the desktop's member card does: their own mood picture (asked
// for by their cast id, so it is never the chat's one mood) and their own
// recovery line under the Lust line. Relay twin (the real chat sends both):
// test/services/web/needs_bars_group_gate_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { Realism } from './chatTypes';

// The panel's own requests (tools, places) never settle: nothing they would
// load is part of this pin, and nothing lands after the test.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');

const base: Realism = {
  realismEnabled: true,
  bond: { score: 12, tier: 'Friendly', percent: 0.52 },
  longTerm: { score: 4, tier: 'Warm', percent: 0.51 },
  trust: { level: 8, tier: 'Some', percent: 0.54 },
  emotion: 'sad',
  emotionIntensity: 'mild',
  mood: 'sad',
  arousal: { level: 20, tier: 'Warm' },
  lustOn: true,
  fixation: '',
  needsEnabled: false,
  needs: {},
};

let container: HTMLDivElement;
let root: Root;

function render(realism: Realism, extra: Record<string, unknown> = {}) {
  act(() => {
    root.render(
      createElement(ChatInsight, {
        realism,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: true,
        focusedIsHost: false,
        focusedAvatarUrl: '/api/groups/g1/members/m2/avatar',
        toolsKey: 0,
        focusedId: 'm2',
        groupId: 'g1',
        onCommand: () => {},
        ...extra,
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

const portrait = () => container.querySelector<HTMLImageElement>('.portrait-wrap img.portrait');
const lines = () => [...container.querySelectorAll('.stat-line')].map((l) => l.textContent);

describe("a focused group member's insight panel", () => {
  it("asks for the member's own mood picture, then their member picture", () => {
    render({ ...base, expressionLabel: 'sadness' });
    const src = portrait()?.getAttribute('src') ?? '';
    expect(src).toContain('/api/chat/expression-avatar?participant=m2');
    expect(src).toContain('v=sadness');
    act(() => {
      portrait()!.dispatchEvent(new Event('error'));
    });
    expect(portrait()?.getAttribute('src')).toBe('/api/groups/g1/members/m2/avatar');
  });

  it('shows no flat placeholder picture when the mood picture fails', () => {
    render(base, { focusedPlaceholderPortrait: true });
    act(() => {
      portrait()!.dispatchEvent(new Event('error'));
    });
    expect(portrait()).toBeNull();
  });

  it('shows their own recovery under the Lust line while Afterglow runs', () => {
    render({ ...base, refractoryLabel: 'Refractory: about 30 min' });
    expect(lines()).toContain('Refractory: about 30 min');

    render({ ...base, lustOn: false, refractoryLabel: 'Refractory: about 30 min' });
    expect(lines().some((l) => l?.includes('Refractory'))).toBe(false);

    render({ ...base, refractoryLabel: '' });
    expect(lines().some((l) => l?.includes('Refractory'))).toBe(false);
  });
});
