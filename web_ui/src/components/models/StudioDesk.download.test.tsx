// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A finished CivitAI download is selected on the desk only when the graph on
// it can load the file, by the computer's own answer; otherwise the person is
// told where it is. The model is never picked by a guess made on the phone.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, calls, click, container, createElement, mount, posts, readyFacts, reset, serve, settle,
  text, type, unmount, until,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');

const props = (over: Record<string, unknown> = {}) => ({
  cfg: baseConfig,
  onConfig: vi.fn(),
  save: vi.fn().mockResolvedValue(true),
  totpEnabled: false,
  prompt: '',
  onPrompt: vi.fn(),
  onGenerate: vi.fn(),
  civitaiPollMs: 5,
  ...over,
});

const done = { jobId: 'j1', name: 'portrait.safetensors', state: 'done', received: 1, total: 1, percent: 100 };

afterEach(() => {
  unmount();
  reset();
});

/** Opens a CivitAI sheet, searches, and taps the row until the note shows. */
const download = async (
  label: string,
  choice: unknown,
  over: Record<string, unknown> = {},
  routes: Record<string, unknown> = {},
) => {
  serve({
    'GET /api/image/studio/ready': readyFacts,
    'GET /api/image/civitai/credential': { saved: true },
    'GET /api/image/civitai/installed': { bases: [], models: [], loras: [] },
    'GET /api/image/civitai/search': {
      items: [{ filename: 'portrait.safetensors', versionId: 42, type: 'Checkpoint', adult: false }],
    },
    'POST /api/image/civitai/download': { ...done, state: 'running', percent: 0 },
    'GET /api/image/civitai/download/status': done,
    'POST /api/image/studio/installed': choice,
    'POST /api/image/studio/pick': baseConfig,
    ...routes,
  });
  const p = props(over);
  mount(createElement(StudioDesk, p));
  await settle();
  click(label);
  await settle();
  type('input[aria-label="Search"]', 'portrait');
  click('Search');
  await settle();
  click('portrait.safetensors');
  await until(() => posts('/api/image/studio/installed').length > 0);
  await settle(6);
  return p;
};

describe('a downloaded model', () => {
  it('is asked about for the graph on the desk, and selected in the slot the computer names', async () => {
    const p = await download('Get a model from CivitAI', {
      accept: true, kind: 'comfy', token: '%MODEL_DIFFUSION%', workflowId: 'z_image_turbo',
    });

    expect(posts('/api/image/studio/installed').map((c) => c.body)).toEqual([
      { filename: 'portrait.safetensors', lora: false, workflowId: 'z_image_turbo' },
    ]);
    expect(posts('/api/image/studio/pick').map((c) => c.body)).toEqual([
      { kind: 'support', mode: 'create', token: '%MODEL_DIFFUSION%', file: 'portrait.safetensors' },
    ]);
    expect(p.onConfig).toHaveBeenCalledWith(baseConfig);
    expect(text()).toContain('Saved to your models folder on this computer.');
    expect(text()).not.toContain('Pick it with Change model');
  });

  it('is selected as the model on a backend with one model slot', async () => {
    await download('Get a model from CivitAI', { accept: true, kind: 'slot' }, { cfg: { ...baseConfig, backend: 'a1111' } });

    expect(posts('/api/image/studio/pick').map((c) => c.body)).toEqual([
      { kind: 'model', mode: 'create', file: 'portrait.safetensors' },
    ]);
  });

  it('is left unselected, and the person is told where to find it, when the graph cannot load it', async () => {
    await download('Get a model from CivitAI', { accept: false });

    expect(posts('/api/image/studio/pick')).toHaveLength(0);
    expect(text()).toContain('Saved to your models folder on this computer. Pick it with Change model.');
  });
});

describe('a downloaded LoRA', () => {
  it('fills the slot the computer chose', async () => {
    const loras = [{ file: 'portrait.safetensors', weight: 0.8 }];
    const p = await download('Get a LoRA from CivitAI', { accept: true, kind: 'lora', loras });

    expect(p.save).toHaveBeenCalledWith({ loras });
    expect(text()).toContain('Saved to your models folder on this computer.');
  });

  it('says every slot is full', async () => {
    await download('Get a LoRA from CivitAI', { accept: false, kind: 'lora-full' });
    expect(text()).toContain('Saved to your models folder on this computer. All LoRA slots are full.');
  });

  it('says where an Automatic1111 LoRA is', async () => {
    await download('Get a LoRA from CivitAI', { accept: false }, { cfg: { ...baseConfig, backend: 'a1111' } });
    expect(text()).toContain('It is in the Lora folder.');
    expect(text()).not.toContain('Pick it with Add under LoRA');
  });

  it('says to pick it with Add under LoRA elsewhere', async () => {
    await download('Get a LoRA from CivitAI', { accept: false });
    expect(text()).toContain('Pick it with Add under LoRA.');
  });
});

describe('when the computer cannot say', () => {
  it('the file is still saved, and the person is told where it is', async () => {
    await download('Get a model from CivitAI', { accept: false }, {}, {
      'POST /api/image/studio/installed': () => {
        throw new Error('offline');
      },
    });

    expect(text()).toContain('Saved to your models folder on this computer. Pick it with Change model.');
    expect(container.querySelector('progress')).toBeNull();
    expect(calls.filter((c) => c.path === '/api/image/studio/pick')).toEqual([]);
  });
});
