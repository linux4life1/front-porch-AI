// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Discussion is opt-in per card. An older hub omits commentsEnabled, and that
// must read as off: a visitor sees no Discussion and the phone never asks the
// hub for comments. Red proof: reading the flag as `!== false` shows the
// section and calls comments() for the missing case.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { StoopCardDetail } from '../../stoop/stoopTypes';

const { comments } = vi.hoisted(() => ({
  comments: vi.fn(() => {
    throw new Error('Discussion is off; the phone must not ask for comments');
  }),
}));

vi.mock('../../stoop/StoopContext', () => ({
  useStoop: () => ({ user: { id: 'visitor', emailVerified: true } }),
}));

vi.mock('../../stoop/stoopApi', () => ({
  stoop: { comments },
  stoopErrorText: (e: unknown) => String(e),
}));

const { StoopDiscussion } = await import('./StoopDiscussion');

let container: HTMLDivElement;
let root: Root;

function detail(flags: Partial<StoopCardDetail>): StoopCardDetail {
  return {
    id: 'card-1',
    name: 'Porch Neighbor',
    creator: { id: 'owner' },
    ...flags,
  } as StoopCardDetail;
}

function render(d: StoopCardDetail) {
  act(() => {
    root.render(createElement(StoopDiscussion, { detail: d }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
    true;
  comments.mockClear();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('StoopDiscussion fails closed', () => {
  it('shows nothing when the hub leaves commentsEnabled out', () => {
    render(detail({}));
    expect(container.textContent).not.toContain('Discussion');
    expect(comments).not.toHaveBeenCalled();
  });

  it('shows nothing when commentsEnabled is false or locked', () => {
    render(detail({ commentsEnabled: false }));
    expect(container.textContent).not.toContain('Discussion');
    render(detail({ commentsEnabled: true, commentsLocked: true }));
    expect(container.textContent).not.toContain('Discussion');
    expect(comments).not.toHaveBeenCalled();
  });
});
