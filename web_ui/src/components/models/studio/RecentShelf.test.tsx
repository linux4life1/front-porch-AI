// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Issue #667: the phone's Recent shelf shows what the computer kept, brings a
// picture back, stars, deletes, clears and sets how many to keep.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import {
  click, container, createElement, mount, pickOption, posts, reset, serve, settle, text, unmount,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { RecentShelf, recentStamp, shelfTitle } = await import('./RecentShelf');

afterEach(() => {
  unmount();
  reset();
});

const entry = (name: string, over: Record<string, unknown> = {}) => ({
  name,
  prompt: `prompt for ${name}`,
  style: 'cinematic',
  mode: 'create',
  model: 'juggernaut',
  createdAt: new Date().toISOString(),
  kept: false,
  bytes: 1000,
  url: `/api/image/saved/${name}`,
  ...over,
});

const view = (entries: unknown[], limit = 50) => ({
  limit,
  choices: [50, 200, -1, 0],
  folder: '/x/studio-recent',
  usage: { bytes: 2000, count: entries.length, kept: 0 },
  entries,
});

const GET = 'GET /api/image/recent';

function shelf(over: Record<string, unknown> = {}) {
  const props = {
    refreshKey: 0,
    selected: null,
    onRestore: vi.fn(),
    onEdit: vi.fn(),
    onError: vi.fn(),
    ...over,
  };
  mount(createElement(RecentShelf, props));
  return props;
}

const thumb = (name: string) =>
  container.querySelector<HTMLButtonElement>(`li img[src="/api/image/saved/${name}"]`)!.closest('button')!;

describe('the Recent shelf', () => {
  it('lists what the computer kept and brings a picture back on tap', async () => {
    serve({ [GET]: view([entry('rec_2.png', { kept: true }), entry('rec_1.png', { mode: 'edit' })]) });
    const props = shelf();
    await settle();
    expect(text()).toContain('Recent · 1 of 50 · 1 starred');
    expect(container.querySelectorAll('.fp-recent-star')).toHaveLength(1);
    expect(text()).toContain('Edit · ');

    act(() => thumb('rec_1.png').click());
    expect(props.onRestore).toHaveBeenCalledWith(expect.objectContaining({ name: 'rec_1.png', prompt: 'prompt for rec_1.png' }));
  });

  it('stars, sends to Edit and deletes from a picture’s menu', async () => {
    serve({
      [GET]: view([entry('rec_1.png')]),
      'POST /api/image/recent/keep': { entry: entry('rec_1.png', { kept: true }) },
      'POST /api/image/recent/delete': { deleted: 'rec_1.png' },
    });
    const props = shelf();
    await settle();

    click('⋯');
    click('Star (never trim)');
    await settle();
    expect(posts('/api/image/recent/keep')[0].body).toEqual({ name: 'rec_1.png', kept: true });

    click('⋯');
    click('Edit this picture');
    expect(props.onEdit).toHaveBeenCalledWith(expect.objectContaining({ name: 'rec_1.png' }));

    click('⋯');
    click('Delete');
    await settle();
    expect(posts('/api/image/recent/delete')[0].body).toEqual({ name: 'rec_1.png' });
  });

  it('asks before clearing, and keeps starred pictures out of the count', async () => {
    serve({
      [GET]: view([entry('rec_3.png', { kept: true }), entry('rec_2.png'), entry('rec_1.png')]),
      'POST /api/image/recent/clear': { cleared: 2 },
    });
    shelf();
    await settle();
    click('Clear unstarred');
    expect(text()).toContain('Delete 2 unstarred pictures? Starred ones stay.');
    expect(posts('/api/image/recent/clear')).toHaveLength(0);
    click('Clear');
    await settle();
    expect(posts('/api/image/recent/clear')).toHaveLength(1);
  });

  it('stores a new limit, and Off hides unstarred pictures', async () => {
    serve({
      [GET]: view([entry('rec_1.png')]),
      'POST /api/image/recent/limit': view([entry('rec_1.png')], 0),
    });
    shelf();
    await settle();
    pickOption('select[aria-label="How many Recent pictures to keep"]', '0');
    await settle();
    expect(posts('/api/image/recent/limit')[0].body).toEqual({ limit: 0 });
    expect(text()).toContain('Recent · off');
    expect(text()).toContain('Recent is off. Pictures stay only when you save them.');
    expect(container.querySelector('li')).toBeNull();
  });

  it('shows nothing against a computer with no shelf', async () => {
    serve({});
    shelf();
    await settle();
    expect(container.querySelector('[data-testid="studio-recent-shelf"]')).toBeNull();
  });
});

describe('Recent shelf words', () => {
  it('names the time a picture was made', () => {
    const now = new Date(2026, 10, 2, 21, 50);
    expect(recentStamp(new Date(2026, 10, 2, 21, 41), now)).toBe('9:41 pm');
    expect(recentStamp(new Date(2026, 10, 2, 0, 5), now)).toBe('12:05 am');
    expect(recentStamp(new Date(2026, 10, 1, 23, 0), now)).toBe('Yesterday');
  });

  it('counts unstarred pictures against the limit', () => {
    const kept = { kept: true } as never;
    const loose = { kept: false } as never;
    expect(shelfTitle({ limit: 50, entries: [kept, loose, loose] })).toBe('Recent · 2 of 50 · 1 starred');
    expect(shelfTitle({ limit: -1, entries: [loose] })).toBe('Recent · 1');
    expect(shelfTitle({ limit: 0, entries: [] })).toBe('Recent · off');
  });
});
