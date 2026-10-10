// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import { afterEach, expect, it, vi } from 'vitest';
import { act } from 'react';
import { click, container, createElement, gets, mount, reset, serve, settle, unmount } from '../components/models/studio/deskTestKit';
vi.mock('../api/client', async () => (await import('../components/models/studio/deskTestKit')).clientMock);
const { ImageBatchesPage } = await import('./ImageBatchesPage');
afterEach(() => { unmount(); reset(); vi.useRealTimers(); });
const idle = { running: false, working: false, jobs: [] };
it('refreshes externally prepared work until controls unlock', async () => {
  let queue = { ...idle, working: true };
  serve({ 'GET /api/characters': [], 'GET /api/folders': {folders: []}, 'GET /api/image/batches': () => queue });
  mount(createElement(ImageBatchesPage)); await settle();
  expect(container.querySelector('fieldset')!.disabled).toBe(true);
  queue = { ...idle, working: false };
  await act(async () => { await new Promise((done) => setTimeout(done, 2100)); });
  expect(gets('/api/image/batches').length).toBeGreaterThan(1);
  expect(container.querySelector('fieldset')!.disabled).toBe(false);
});
it('focus refresh cannot invalidate a pending mutation completion', async () => {
  let resolve!: (value: typeof idle) => void;
  let queue = idle;
  serve({ 'GET /api/characters': [{id:'c1',name:'Card'}], 'GET /api/folders': {folders: []},
    'GET /api/image/batches': () => queue,
    'POST /api/image/batches/prepare': () => new Promise((done) => { resolve = done; queue = {...idle, working: true}; }),
  });
  mount(createElement(ImageBatchesPage)); await settle();
  act(() => container.querySelector<HTMLInputElement>('.batch-characters input')!.click());
  click('Prepare for 1 characters'); await settle();
  act(() => window.dispatchEvent(new Event('focus'))); await settle();
  queue = idle;
  await act(async () => resolve(idle)); await settle();
  click('Prepare'); await settle();
  expect(container.querySelector('fieldset')!.disabled).toBe(false);
});
