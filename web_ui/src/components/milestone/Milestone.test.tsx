// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The web milestone card and Moments (docs/design/boons-and-bogies.md §7) —
// the same words and answers as the desktop card
// (test/ui/widgets/milestone_card_test.dart): the card's words, group
// naming, replay, the answer body the host's growth route expects, the
// bogey-cap line, and the Moments rows.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { MilestoneShowing, MilestoneViewJson } from './milestoneTypes';

const posts: { url: string; body: Record<string, unknown> }[] = [];
let postReply: Record<string, unknown> = {};

vi.mock('../../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => new Promise(() => {}),
    post: (url: string, body: Record<string, unknown>) => {
      posts.push({ url, body });
      return Promise.resolve(postReply);
    },
  },
}));

const { MilestoneModal } = await import('./MilestoneModal');
const { MomentsSection, MomentsUnreadDot } = await import('./Moments');

function view(extra: Partial<MilestoneViewJson> = {}): MilestoneViewJson {
  return {
    id: 'm1',
    kind: 'new_boon',
    status: 'pending',
    statusLabel: '',
    seen: false,
    title: 'New boon',
    pill: 'BOON',
    tierLine: 'Novice · new',
    text: 'catches what falls before it lands',
    receipt: 'Seen in #14 and #18',
    ask: '',
    ownerName: 'Mira Vale',
    inGroup: false,
    meter: 0.3,
    ...extra,
  };
}

function showing(extra: Partial<MilestoneShowing> = {}): MilestoneShowing {
  return { ...view(), replaying: false, seed: 7, ...extra };
}

let container: HTMLDivElement;
let root: Root;

async function render(el: ReturnType<typeof createElement>) {
  await act(async () => {
    root.render(el);
    await Promise.resolve();
  });
}

const text = () => container.textContent ?? '';
const button = (label: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent === label);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  // Reduce motion: no canvas loop in jsdom.
  window.matchMedia = ((q: string) => ({
    matches: q.includes('reduced-motion'),
    media: q,
    addEventListener() {},
    removeEventListener() {},
  })) as unknown as typeof window.matchMedia;
  posts.length = 0;
  postReply = {};
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the card', () => {
  it('shows the approved words and Reject / Accept', async () => {
    await render(createElement(MilestoneModal, { milestone: showing() }));
    expect(text()).toContain('Milestone');
    expect(text()).toContain('New boon');
    expect(text()).toContain('BOON');
    expect(text()).toContain('catches what falls before it lands');
    expect(text()).toContain('Seen in #14 and #18');
    expect(button('Reject')).toBeTruthy();
    expect(button('Accept')).toBeTruthy();
    expect(text()).not.toContain('Mira Vale');
  });

  it('names the member in a group; Master shows its badge and ask', async () => {
    await render(
      createElement(MilestoneModal, {
        milestone: showing({
          kind: 'master_bogey',
          pill: 'BOGEY',
          title: 'Master · bogey',
          ask: 'This has become part of who Mira Vale is. Make it permanent?',
          inGroup: true,
        }),
      }),
    );
    expect(text()).toContain('Mira Vale');
    expect(text()).toContain('MASTER');
    expect(text()).toContain('Make it permanent?');
  });

  it('a replay offers only Close, which dismisses', async () => {
    await render(createElement(MilestoneModal, { milestone: showing({ replaying: true }) }));
    expect(button('Accept')).toBeUndefined();
    await act(async () => {
      button('Close')!.click();
      await Promise.resolve();
    });
    expect(posts.at(-1)?.body).toEqual({ action: 'milestoneDismiss' });
  });

  it('Accept posts the answer the host route expects', async () => {
    await render(createElement(MilestoneModal, { milestone: showing() }));
    await act(async () => {
      button('Accept')!.click();
      await Promise.resolve();
    });
    expect(posts).toEqual([
      {
        url: '/api/chat/tools/growth',
        body: { action: 'milestoneAnswer', momentId: 'm1', accept: true },
      },
    ]);
  });

  it('a full bogey cap keeps the card and says why', async () => {
    postReply = { milestoneOutcome: 'bogeyCapFull' };
    await render(
      createElement(MilestoneModal, {
        milestone: showing({ kind: 'new_bogey', pill: 'BOGEY', title: 'New bogey' }),
      }),
    );
    await act(async () => {
      button('Accept')!.click();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(text()).toContain('already carries three bogies');
  });
});

describe('Moments', () => {
  it('counts unread and pending in the header dot', async () => {
    await render(
      createElement(MomentsUnreadDot, {
        moments: [view(), view({ id: 'm2', status: 'accepted', seen: true })],
      }),
    );
    expect(text()).toBe('1 new');
  });

  it('a pending row answers inline; a decided one replays', async () => {
    const onChanged = vi.fn();
    await render(
      createElement(MomentsSection, {
        moments: [
          view(),
          view({
            id: 'm2',
            status: 'accepted',
            statusLabel: 'Accepted',
            seen: true,
            title: 'Master · boon',
          }),
        ],
        query: '?participant=mira',
        onChanged,
      }),
    );
    expect(text()).toContain('ASKS');
    expect(text()).toContain('Accepted');
    expect(text()).not.toContain('accepted');
    await act(async () => {
      button('Accept')!.click();
      await Promise.resolve();
    });
    await act(async () => {
      button('Replay')!.click();
      await Promise.resolve();
    });
    expect(posts.map((p) => [p.url, p.body])).toEqual([
      [
        '/api/chat/tools/growth?participant=mira',
        { action: 'milestoneAnswer', momentId: 'm1', accept: true },
      ],
      ['/api/chat/tools/growth?participant=mira', { action: 'milestoneReplay', momentId: 'm2' }],
    ]);
    expect(onChanged).toHaveBeenCalledTimes(2);
  });
});
