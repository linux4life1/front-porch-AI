// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Choosing on the phone: a model, a graph, an encoder or a LoRA is sent to the
// computer as the choice made, for the mode on the desk, and the computer's
// answer becomes what the desk shows.

import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, blur, button, calls, click, container, createElement, field, gets, mount, posts, sheetText,
  readyFacts, refuse, reset, serve, settle, text, type, unmount,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');

const props = (over: Record<string, unknown> = {}) => ({
  cfg: baseConfig,
  onConfig: vi.fn(),
  save: vi.fn().mockResolvedValue(true),
  totpEnabled: false,
  prompt: 'a quiet porch',
  onPrompt: vi.fn(),
  onGenerate: vi.fn(),
  ...over,
});

const catalog = {
  deskDiscovery: ['z_image_turbo_bf16.safetensors', 'flux1-dev-fp8.safetensors'],
  graphs: [
    { id: 'z_image_turbo', title: 'Z-Image Turbo', detail: 'Text to image · z_image_turbo', group: 'Text to image graphs' },
    { id: 'comfy:userdata:porch', title: 'Porch', detail: 'Text to image · comfy:userdata:porch', group: 'Saved on this Comfy' },
  ],
  editGraphs: [
    { id: 'qwen_image_edit', title: 'Qwen-Image-Edit', detail: 'Edit · qwen_image_edit', group: 'Edit graphs' },
    { id: 'comfy:userdata:relight', title: 'Relight', detail: 'Edit · comfy:userdata:relight', group: 'Saved on this Comfy' },
  ],
};

afterEach(() => {
  unmount();
  reset();
});

const boot = async (over: Record<string, unknown> = {}, routes: Record<string, unknown> = {}) => {
  serve({ 'GET /api/image/studio/ready': readyFacts, 'GET /api/image/comfy-catalog': catalog, ...routes });
  const p = props(over);
  mount(createElement(StudioDesk, p));
  await settle();
  return p;
};

describe('Change model', () => {
  it('lists what the computer has and sends the choice for the mode', async () => {
    const next = { ...baseConfig, comfyCreateWorkflowId: 'flux' };
    const p = await boot({}, { 'POST /api/image/studio/pick': next });

    click('Change model');
    await settle();
    expect(text()).toContain('flux1-dev-fp8.safetensors');
    click('flux1-dev-fp8.safetensors');
    await settle();

    expect(posts('/api/image/studio/pick').map((c) => c.body)).toEqual([
      { kind: 'model', mode: 'create', file: 'flux1-dev-fp8.safetensors' },
    ]);
    expect(p.onConfig).toHaveBeenCalledWith(next);
    expect(container.querySelector('[role="dialog"]')).toBeNull();
    // The Ready line is read again for what was chosen.
    expect(gets('/api/image/studio/ready').length).toBeGreaterThan(1);
  });

  it('sends the choice for Edit when the desk is on Edit', async () => {
    await boot({}, { 'POST /api/image/studio/pick': baseConfig });
    click('Edit');
    await settle();

    click('Change model');
    await settle();
    expect(gets('/api/image/comfy-catalog').at(-1)!.path).toContain('mode=edit');
    click('flux1-dev-fp8.safetensors');
    await settle();

    expect(posts('/api/image/studio/pick')[0].body).toMatchObject({ mode: 'edit' });
  });

  it('can be typed in, and can be searched', async () => {
    await boot({}, { 'POST /api/image/studio/pick': baseConfig });
    click('Change model');
    await settle();

    type('input[aria-label="Search files"]', 'flux1');
    expect(sheetText()).toContain('flux1-dev-fp8.safetensors');
    expect(sheetText()).not.toContain('z_image_turbo_bf16.safetensors');
    click('Use flux1');
    await settle();

    expect(posts('/api/image/studio/pick')[0].body).toEqual({ kind: 'model', mode: 'create', file: 'flux1' });
  });

  it('says what the computer refused', async () => {
    await boot({}, { 'POST /api/image/studio/pick': refuse(400, 'That name is not usable.') });
    click('Change model');
    await settle();
    click('flux1-dev-fp8.safetensors');
    await settle();

    expect(text()).toContain('That name is not usable.');
  });

  it('uses Draw Things\' own list on Draw Things', async () => {
    await boot(
      { cfg: { ...baseConfig, backend: 'drawthings' } },
      { 'GET /api/image/local-catalog': { models: ['flux_2_klein_9b_q6p.ckpt'], loras: [] } },
    );
    click('Change model');
    await settle();

    expect(text()).toContain('flux_2_klein_9b_q6p.ckpt');
    expect(gets('/api/image/comfy-catalog')).toHaveLength(0);
  });
});

describe('the files a graph also loads', () => {
  it('lists the slots the computer says the graph has', async () => {
    await boot();
    expect(text()).toContain('This graph also loads');
    expect(text()).toContain('qwen_3_4b.safetensors');
    expect(text()).toContain('Not chosen');
  });

  it('says so when the graph has none', async () => {
    await boot(
      {},
      {
        'GET /api/image/studio/ready': {
          ...readyFacts,
          slots: [{ token: '%MODEL_CHECKPOINT%', label: 'Checkpoint', file: 'sdxl.safetensors' }],
        },
      },
    );
    expect(text()).toContain('This graph has no text encoder or VAE slot.');
    expect(text()).not.toContain('This graph also loads');
  });

  it('marks the files that look wrong last, and sends the slot', async () => {
    await boot(
      {},
      {
        'GET /api/image/comfy-catalog': {
          ...catalog,
          slotFiles: { files: ['qwen_3_4b.safetensors', 'clip_l.safetensors'], unfit: ['clip_l.safetensors'] },
        },
        'POST /api/image/studio/pick': baseConfig,
      },
    );
    const change = [...container.querySelectorAll('button')].filter((b) => b.textContent === 'Change');
    act(() => change[0].click());
    await settle();

    expect(gets('/api/image/comfy-catalog').at(-1)!.path).toBe('/api/image/comfy-catalog?mode=create&token=%25MODEL_CLIP%25');
    expect(text()).toContain('Change text encoder');
    expect(text()).toContain('clip_l.safetensors (may not fit z_image_turbo_bf16.safetensors)');
    expect(text()).not.toContain('qwen_3_4b.safetensors (may not fit');
    click('clip_l.safetensors (may not fit z_image_turbo_bf16.safetensors)');
    await settle();

    expect(posts('/api/image/studio/pick')[0].body).toEqual({
      kind: 'support', mode: 'create', token: '%MODEL_CLIP%', file: 'clip_l.safetensors',
    });
  });
});

describe('Change graph', () => {
  it('reads the computer\'s lists once and sends the graph for the mode', async () => {
    await boot({}, { 'POST /api/image/studio/pick': baseConfig });

    click('Change graph');
    await settle();
    expect(gets('/api/image/comfy-catalog')).toHaveLength(1);
    expect(sheetText()).toContain('Change graph — Create');
    expect(sheetText()).toContain('comfy:userdata:porch');
    expect(sheetText()).not.toContain('Relight');
    click('Porch');
    await settle();

    expect(posts('/api/image/studio/pick')[0].body).toEqual({ kind: 'graph', mode: 'create', id: 'comfy:userdata:porch' });
  });

  it('lists the Edit graphs in Edit', async () => {
    await boot({}, { 'POST /api/image/studio/pick': baseConfig });
    click('Edit');
    await settle();

    click('Change graph');
    await settle();

    expect(sheetText()).toContain('Change graph — Edit');
    expect(sheetText()).toContain('Relight');
    expect(sheetText()).not.toContain('comfy:userdata:porch');
    click('Relight');
    await settle();
    expect(posts('/api/image/studio/pick')[0].body).toMatchObject({ mode: 'edit', id: 'comfy:userdata:relight' });
  });

  it('finds a graph of the other mode by search and sends it for that mode', async () => {
    await boot({}, { 'POST /api/image/studio/pick': baseConfig });
    click('Change graph');
    await settle();

    type('input[aria-label="Search graphs"]', 'relight');
    click('Use it for Edit');
    await settle();

    expect(posts('/api/image/studio/pick')[0].body).toEqual({ kind: 'graph', mode: 'edit', id: 'comfy:userdata:relight' });
  });

  it('reads the lists again only when it is opened again', async () => {
    await boot();
    click('Change graph');
    await settle();
    click('Close');
    click('Change graph');
    await settle();

    expect(gets('/api/image/comfy-catalog')).toHaveLength(2);
  });
});

describe('LoRAs', () => {
  const routes = {
    'GET /api/image/comfy-catalog': {
      ...catalog,
      loras: ['zit_style.safetensors', 'flux_style.safetensors'],
      loraFacts: [
        { file: 'zit_style.safetensors', family: 'zImage', meta: true },
        { file: 'flux_style.safetensors', family: 'flux', meta: true },
      ],
    },
  };

  it('sorts the files by whether they fit and fills the first empty slot', async () => {
    const cfg = { ...baseConfig, loras: [{ file: 'first.safetensors', weight: 0.5 }] };
    const p = await boot({ cfg }, routes);

    click('Add');
    await settle();
    expect(gets('/api/image/comfy-catalog').at(-1)!.path).toContain('lora=1');
    const fits = text().indexOf('Matches this model');
    const others = text().indexOf('Other bases');
    expect(text().indexOf('zit_style.safetensors')).toBeGreaterThan(fits);
    expect(text().indexOf('zit_style.safetensors')).toBeLessThan(others);
    expect(text().indexOf('flux_style.safetensors')).toBeGreaterThan(others);
    click('zit_style.safetensors');
    await settle();

    const saved = p.save.mock.calls[0][0].loras;
    expect(saved).toHaveLength(8);
    expect(saved[0]).toEqual({ file: 'first.safetensors', weight: 0.5 });
    expect(saved[1]).toEqual({ file: 'zit_style.safetensors', weight: 0.8 });
  });

  it('says when every slot is full', async () => {
    const full = Array.from({ length: 8 }, (_, i) => ({ file: `l${i}.safetensors`, weight: 0.8 }));
    const p = await boot({ cfg: { ...baseConfig, loras: full } }, routes);

    click('Add');
    await settle();
    click('zit_style.safetensors');
    await settle();

    expect(p.save).not.toHaveBeenCalled();
    expect(text()).toContain('All LoRA slots are full.');
  });

  it('changes a weight and removes one', async () => {
    const cfg = { ...baseConfig, loras: [{ file: 'a.safetensors', weight: 0.5 }, { file: 'b.safetensors', weight: 0.7 }] };
    const p = await boot({ cfg });

    type('input[aria-label="Weight a.safetensors"]', '0.9');
    blur('input[aria-label="Weight a.safetensors"]');
    await settle();
    expect(p.save.mock.calls[0][0].loras[0]).toEqual({ file: 'a.safetensors', weight: 0.9 });

    click('Remove b.safetensors');
    await settle();
    expect(p.save.mock.calls[1][0].loras[1]).toEqual({ file: '', weight: 0.7 });
  });
});

describe('size and the rest', () => {
  it('sends a preset, and snaps a typed side', async () => {
    const p = await boot();

    click('512×512');
    expect(p.save).toHaveBeenCalledWith({ size: '512x512' });

    type('input[aria-label="Width"]', '300');
    blur('input[aria-label="Width"]');
    expect(p.save).toHaveBeenLastCalledWith({ size: '320x1024' });
  });

  it('shows what will be sent', async () => {
    await boot({ cfg: { ...baseConfig, size: '1536x1024' } });
    expect(text()).toContain('Sends 1536×1024. Each side snaps to a multiple of 64, from 256 to 2048.');
  });

  it('keeps steps, sampler and the rest behind Advanced', async () => {
    const p = await boot();
    expect(container.querySelector('[aria-label="Steps"]')).toBeNull();

    click(/^Advanced ▸/);
    expect(field('[aria-label="Steps"]')).not.toBeNull();
    type('[aria-label="Negative prompt"]', 'blurry');
    blur('[aria-label="Negative prompt"]');
    expect(p.save).toHaveBeenCalledWith({ negativePrompt: 'blurry' });
    act_change('[aria-label="Review prompts"]', p);
    expect(p.save).toHaveBeenCalledWith({ promptReview: true });
  });

  it('lists the Draw Things samplers the computer sent', async () => {
    const p = await boot({ cfg: { ...baseConfig, backend: 'drawthings' } });
    click(/^Advanced ▸/);

    const select = field<HTMLSelectElement>('[aria-label="Draw Things sampler"]');
    expect([...select.options].map((o) => o.textContent)).toEqual(['DDIM Trailing', 'Euler a']);
    expect(container.querySelector('[aria-label="Steps"]')).toBeNull();
    expect(p.save).not.toHaveBeenCalled();
  });
});

function act_change(selector: string, p: { save: unknown }) {
  void p;
  const el = field(selector);
  el.click();
}
