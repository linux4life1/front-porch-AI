// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, expect, it, vi } from 'vitest';
import { act } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { click, container, createElement, mount, posts, reset, serve, settle, text, type, unmount } from '../components/models/studio/deskTestKit';
vi.mock('../api/client', async () => (await import('../components/models/studio/deskTestKit')).clientMock);
const { ImageBatchesPage } = await import('./ImageBatchesPage');
afterEach(() => { unmount(); reset(); });

it('prepares additional portraits for multiple characters and reviews a separate retry', async () => {
  const job = { id: 'job1', characterId: 'c1', characterName: 'First character', kind: 'additional', label: 'Additional portrait', state: 'waiting', prompt: 'In a garden', seed: 17, size: '1024x1024' };
  const queue = (jobs: unknown[] = []) => ({ running: false, working: false, jobs });
  serve({
    'GET /api/characters': [{ id: 'c1', name: 'First character' }, { id: 'c2', name: 'Second character' }],
    'GET /api/image/batches': queue(),
    'POST /api/image/batches/prepare': queue([job]),
    'POST /api/image/batches/start': queue([{ ...job, state: 'review', candidate: 'picture.png' }]),
    'POST /api/image/batches/job1/review': queue([{ ...job, state: 'review' }, { ...job, id: 'job2' }]),
  });
  mount(createElement(MemoryRouter, null, createElement(ImageBatchesPage)));
  await settle();
  type('textarea', '{character} in a garden');
  const boxes = [...container.querySelectorAll<HTMLInputElement>('.batch-characters input')];
  act(() => boxes.forEach((box) => box.click()));
  click('Prepare for 2 characters');
  await settle();
  expect(posts('/api/image/batches/prepare')[0].body).toMatchObject({kind: 'additional', characterIds: ['c1', 'c2'], prompt: '{character} in a garden'});
  click('Start 1 images'); await settle();
  click('Review'); await settle();
  click('Redo…'); await settle();
  type('textarea', 'A refined garden scene');
  click('Add to queue'); await settle();
  expect(posts('/api/image/batches/job1/review')[0].body).toEqual({ action: 'redo', prompt: 'A refined garden scene', newSeed: true });
  expect(text()).toContain('Start 1 images');
  expect(text()).toContain('review');
});

