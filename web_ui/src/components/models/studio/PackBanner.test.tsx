// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The line above the desk while a pack is being made: it shows the pack, stops
// it (and says so, or says why it could not), and asks about the pack only
// while there is one running.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import {
  button, click, container, createElement, gets, mount, posts, refuse, reset, serve, settle, text, unmount,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { PackBanner } = await import('./PackBanner');
const { startPack } = await import('./packApi');

afterEach(() => {
  unmount();
  reset();
});

const view = (over: Record<string, unknown> = {}) => ({
  running: true,
  mode: 'edit',
  origin: 'phone',
  characterId: 'c1',
  characterName: 'Mara',
  total: 4,
  done: 1,
  kept: 1,
  imported: null,
  canImport: false,
  slots: [],
  ...over,
});

const GET = 'GET /api/image/expression-pack';
const CANCEL = 'POST /api/image/expression-pack/cancel';

describe('the pack banner', () => {
  it('shows a pack that is running, and nothing when there is none', async () => {
    serve({ [GET]: view() });
    mount(createElement(PackBanner, {}));
    await settle();
    expect(text()).toContain('Expression pack for Mara: 1 of 4 made.');

    unmount();
    serve({ [GET]: refuse(404, 'No expression pack') });
    mount(createElement(PackBanner, {}));
    await settle();
    expect(container.querySelector('[data-region="pack-banner"]')).toBeNull();
  });

  it('says the pack stopped after Cancel', async () => {
    serve({ [GET]: view(), [CANCEL]: view({ running: false }) });
    mount(createElement(PackBanner, {}));
    await settle();

    click('Cancel pack');
    await settle();

    expect(posts('/api/image/expression-pack/cancel')).toHaveLength(1);
    expect(container.querySelector('[data-region="pack-banner"]')?.textContent).toBe('Pack stopped.');
  });

  it('says why the pack could not be stopped, and keeps the button', async () => {
    serve({ [GET]: view(), [CANCEL]: refuse(500, 'ComfyUI did not answer.') });
    mount(createElement(PackBanner, {}));
    await settle();

    click('Cancel pack');
    await settle();

    expect(container.querySelector('[role="alert"]')?.textContent).toContain('ComfyUI did not answer.');
    expect(button('Cancel pack')).toBeDefined();
  });

  it('asks again only while a pack is running', async () => {
    vi.useFakeTimers();
    try {
      serve({ [GET]: refuse(404, 'No expression pack') });
      mount(createElement(PackBanner, {}));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(20000);
      });
      expect(gets('/api/image/expression-pack')).toHaveLength(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('follows a running pack, and stops asking when it has stopped', async () => {
    vi.useFakeTimers();
    try {
      let n = 0;
      serve({ [GET]: () => (n++ === 0 ? view() : view({ running: false })) });
      mount(createElement(PackBanner, {}));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });
      await act(async () => {
        await vi.advanceTimersByTimeAsync(3100);
      });
      await act(async () => {
        await vi.advanceTimersByTimeAsync(20000);
      });
      expect(gets('/api/image/expression-pack')).toHaveLength(2);
    } finally {
      vi.useRealTimers();
    }
  });

  it('notices a pack started from this phone', async () => {
    let started = false;
    serve({
      [GET]: () => (started ? view() : refuse(404, 'No expression pack')),
      'POST /api/image/expression-pack': () => {
        started = true;
        return view();
      },
    });
    mount(createElement(PackBanner, {}));
    await settle();
    expect(container.querySelector('[data-region="pack-banner"]')).toBeNull();

    await act(async () => {
      await startPack({
        characterId: 'c1', set: 'starter', skipExisting: true, replaceExisting: true, denoise: 0.7, prompt: '',
      });
    });
    await settle();

    expect(text()).toContain('Expression pack for Mara');
  });
});
