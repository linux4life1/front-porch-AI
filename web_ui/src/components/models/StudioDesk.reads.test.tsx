// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desk reads and shows; it changes nothing by itself. A saved or template
// graph, and a model file of another family, stay as the person left them.
// Edit is its own mode with its own Ready, and needs a picture.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, button, calls, choose, clientMock, click, container, createElement, gets, mount, png,
  posts, readyFacts, refuse, reset, serve, settle, text, unmount,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');
void clientMock;

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

afterEach(() => {
  unmount();
  reset();
});

describe('a desk left as the person set it', () => {
  it('writes nothing when the graph is a saved one and the model is another family', async () => {
    const cfg = {
      ...baseConfig,
      comfyCreateWorkflowId: 'comfy:userdata:my_flow',
      comfyCreateModelChoices: { 'comfy:userdata:my_flow/%MODEL_DIFFUSION%': 'chroma_hd.safetensors' },
    };
    serve({
      'GET /api/image/studio/ready': {
        ...readyFacts,
        primary: 'chroma_hd.safetensors',
        loraFamily: 'unknown',
        workflowId: 'comfy:userdata:my_flow',
      },
    });
    const p = props({ cfg });

    mount(createElement(StudioDesk, p));
    await settle();
    click('Edit');
    await settle();
    click('Create');
    await settle();

    expect(text()).toContain('chroma_hd.safetensors');
    expect(text()).toContain('Workflow · Text to image · comfy:userdata:my_flow');
    expect(calls.filter((c) => c.method === 'POST')).toEqual([]);
    expect(p.save).not.toHaveBeenCalled();
    expect(p.onConfig).not.toHaveBeenCalled();
  });

  it('opens and closes every sheet without writing', async () => {
    serve({
      'GET /api/image/studio/ready': readyFacts,
      'GET /api/image/comfy-catalog': { graphs: [], editGraphs: [], deskDiscovery: ['a.safetensors'], loras: [] },
      'GET /api/image/civitai/credential': { saved: true },
      'GET /api/image/civitai/installed': { bases: [], models: [], loras: [] },
    });
    const p = props();
    mount(createElement(StudioDesk, p));
    await settle();

    for (const [open] of [['Change graph'], ['Change model'], ['Add'], ['Get a model from CivitAI']]) {
      click(open);
      await settle();
      click('Close');
      await settle();
    }

    expect(calls.filter((c) => c.method === 'POST')).toEqual([]);
    expect(p.save).not.toHaveBeenCalled();
  });
});

describe('Edit', () => {
  const editFacts = { ...readyFacts, mode: 'edit', workflowId: 'qwen_image_edit', primary: 'qwen_image_edit_2509_fp8.safetensors' };

  const serveModes = () =>
    serve({
      'GET /api/image/studio/ready': (_body: unknown, path: string) =>
        path.includes('mode=edit') ? editFacts : readyFacts,
    });

  it('asks for the Edit graph\'s Ready, and shows the Edit model', async () => {
    serveModes();
    mount(createElement(StudioDesk, props()));
    await settle();
    expect(gets('/api/image/studio/ready').map((c) => c.path)).toEqual(['/api/image/studio/ready?mode=create']);

    click('Edit');
    await settle();

    expect(gets('/api/image/studio/ready').map((c) => c.path)).toContain('/api/image/studio/ready?mode=edit');
    expect(text()).toContain('qwen_image_edit_2509_fp8.safetensors');
    expect(text()).toContain('Workflow · Edit · qwen_image_edit');
  });

  it('cannot generate without a picture, and can with one', async () => {
    serveModes();
    const p = props();
    mount(createElement(StudioDesk, p));
    await settle();
    click('Edit');
    await settle();
    expect(button('Generate')!.disabled).toBe(true);
    expect(text()).toContain('Pick a picture to edit.');

    choose('input[aria-label="Picture file"]', png('me.png'));
    await settle(10);

    expect(button('Generate')!.disabled).toBe(false);
    click('Generate');
    expect(p.onGenerate).toHaveBeenCalledTimes(1);
    const request = p.onGenerate.mock.calls[0][0];
    expect(request.mode).toBe('edit');
    expect(request.picture.kind).toBe('file');
    expect(request.picture.dataUrl).toMatch(/^data:image\/png;base64,/);
  });

  it('can start from the picture the last generate saved', async () => {
    serveModes();
    const p = props({ lastSaved: { name: 'saved_1.png', url: '/api/image/saved/saved_1.png' } });
    mount(createElement(StudioDesk, p));
    await settle();
    click('Edit');
    await settle();

    click('Use the last picture I made');
    await settle();
    click('Generate');

    expect(p.onGenerate.mock.calls[0][0]).toEqual({
      mode: 'edit',
      picture: { kind: 'saved', name: 'saved_1.png', url: '/api/image/saved/saved_1.png' },
    });
  });

  it('a Create needs no picture, and sends one when there is one', async () => {
    serveModes();
    const p = props();
    mount(createElement(StudioDesk, p));
    await settle();

    click('Generate');
    expect(p.onGenerate.mock.calls[0][0]).toEqual({ mode: 'create', picture: null });

    choose('input[aria-label="Picture file"]', png());
    await settle(10);
    click('Generate');
    expect(p.onGenerate.mock.calls[1][0].picture.kind).toBe('file');
  });

  it('refuses a picture that is not a picture, or too large', async () => {
    serveModes();
    mount(createElement(StudioDesk, props()));
    await settle();

    choose('input[aria-label="Picture file"]', new File(['words'], 'notes.txt', { type: 'text/plain' }));
    await settle();
    expect(text()).toContain('That is not a picture.');

    const big = new File([new Uint8Array(12 * 1024 * 1024 + 1)], 'big.png', { type: 'image/png' });
    choose('input[aria-label="Picture file"]', big);
    await settle();
    expect(text()).toContain('That picture is too large.');
    expect(container.querySelector('img[alt=""]')).toBeNull();
  });
});

describe('the Generate button', () => {
  it('waits for Ready, for a prompt, and for the picture being made', async () => {
    serve({ 'GET /api/image/studio/ready': { ...readyFacts, ready: false, kind: 'missingFile' } });
    mount(createElement(StudioDesk, props()));
    await settle();
    expect(button('Generate')!.disabled).toBe(true);
    expect(text()).toContain('Not ready — choose the model files this graph loads.');
    unmount();

    serve({ 'GET /api/image/studio/ready': readyFacts });
    mount(createElement(StudioDesk, props({ prompt: '   ' })));
    await settle();
    expect(button('Generate')!.disabled).toBe(true);
    unmount();

    mount(createElement(StudioDesk, props({ busy: true, progress: 0.4 })));
    await settle();
    expect(button('Generate')!.disabled).toBe(true);
    expect(text()).toContain('Generating…');
    expect(text()).toContain('Painting… 40%');
    expect((container.querySelector('progress[aria-label="Generation progress"]') as HTMLProgressElement).value).toBe(0.4);
  });

  it('says why when the computer cannot be read', async () => {
    serve({ 'GET /api/image/studio/ready': refuse(502, 'down') });
    mount(createElement(StudioDesk, props()));
    await settle();
    expect(button('Generate')!.disabled).toBe(true);
    expect(text()).toContain('Not ready — ComfyUI is not running.');
  });

  it('shows a mismatched LoRA and lets the person press Use anyway', async () => {
    serve({
      'GET /api/image/studio/ready': {
        ...readyFacts,
        ready: false,
        kind: 'loraMismatch',
        blockedLora: 'flux_style.safetensors',
        loraFacts: [{ file: 'flux_style.safetensors', family: 'flux', meta: true }],
      },
    });
    const p = props({ cfg: { ...baseConfig, loras: [{ file: 'flux_style.safetensors', weight: 0.8 }] } });
    mount(createElement(StudioDesk, p));
    await settle();

    expect(text()).toContain('other base');
    expect(text()).toContain('Not ready — LoRA architecture does not match z_image_turbo_bf16.safetensors.');
    click('Use anyway');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ loraOverrideFamily: 'zImage' });
  });

  it('shows the computer\'s words when the loader needs an update', async () => {
    serve({
      'GET /api/image/studio/ready': {
        ...readyFacts,
        ready: false,
        kind: 'needsLoaderUpdate',
        canUpdateLoader: true,
        message: 'This model needs the GGUF loader update. Confirm it on the desktop.',
      },
    });
    mount(createElement(StudioDesk, props()));
    await settle();

    expect(text()).toContain('Not ready — This model needs the GGUF loader update. Confirm it on the desktop.');
    expect(posts('/api/image/studio/pick')).toHaveLength(0);
  });
});
