// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's lore list in a group shows a group-lorebook entry by the Name
// typed for it (the relay sends "Group: <name>"), and when the group's stored
// lorebook cannot be read the panel says so, as the desktop sidebar does.
// Relay twin: test/services/chat/group_lorebook_keyword_turn_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { LoreEntry, Realism } from './chatTypes';

// The panel's own requests (tools, places) never settle: nothing they would
// load is part of this pin, and nothing lands after the test.
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatInsight } = await import('./ChatInsight');

const realism: Realism = {
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

const oak: LoreEntry = {
  key: 'oak, tree',
  name: 'Group: Old Oak',
  isTriggered: true,
  constant: false,
};

let container: HTMLDivElement;
let root: Root;

function render(groupLorebookUnreadable: boolean) {
  act(() => {
    root.render(
      createElement(ChatInsight, {
        realism,
        lorebook: [oak],
        groupLorebookUnreadable,
        authorNote: '',
        authorNoteDepth: 4,
        onSaveAuthorNote: () => {},
        characterId: 'c1',
        isGroup: true,
        focusedIsHost: false,
        toolsKey: 0,
        focusedId: null,
        groupId: 'grp-duet',
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

describe('group lorebook on the phone', () => {
  it('lists the entry by its name', () => {
    render(false);
    const rows = [...container.querySelectorAll('.lore-list .lore')].map((r) => r.textContent);
    expect(rows).toContain('Group: Old Oak');
    expect(container.querySelector('.lore-unreadable')).toBeNull();
  });

  it('says when the group lorebook cannot be read', () => {
    render(true);
    expect(container.querySelector('.lore-unreadable')?.textContent).toMatch(
      /lorebook couldn't be read, so its entries aren't being used/,
    );
  });
});
