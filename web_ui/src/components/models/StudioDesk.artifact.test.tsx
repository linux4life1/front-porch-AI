// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { ImageGen } from './ImageGen';
import { StudioDesk, supportFills, type StudioDeskProps } from './StudioDesk';

vi.mock('../../api/client', () => ({
  api: {
    get: vi.fn(() => Promise.resolve({ ready: true })),
    post: vi.fn().mockResolvedValue({}),
  },
}));

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
  vi.mocked(api.get).mockReset();
  vi.mocked(api.get).mockImplementation(() => Promise.resolve({ ready: true }));
});

const base: StudioDeskProps = {
  backend: 'remote',
  model: 'z_image_turbo_bf16.safetensors',
  size: '1024x1024',
  steps: 8,
  sampler: 'euler',
  workflowId: 'z_image_turbo',
  cfg: 1,
  scheduler: 'simple',
  comfyUrl: 'http://127.0.0.1:8188',
  localUrl: 'http://127.0.0.1:7860',
  drawThingsHost: '127.0.0.1',
  remoteUrl: 'https://example.test',
  onSave: () => {},
};

function Harness(props: Partial<StudioDeskProps>) {
  const [size, setSize] = useState(props.size ?? base.size);
  return createElement(StudioDesk, {
    ...base,
    ...props,
    size,
    onSave: (patch) => {
      if (typeof patch.size === 'string') setSize(patch.size);
      props.onSave?.(patch);
    },
  });
}

function render(extra: Partial<StudioDeskProps> = {}) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(Harness, extra));
  });
}

function button(label: string) {
  return [...container.querySelectorAll('button')].find((b) => b.textContent === label);
}

function mockReadyFacts(rows: { file: string; family: string; meta: boolean }[]) {
  vi.mocked(api.get).mockImplementation((url: string) => {
    if (String(url).includes('/api/image/studio/ready')) {
      return Promise.resolve({ ready: true, loraFacts: rows });
    }
    if (String(url).includes('comfy-catalog')) {
      return Promise.resolve({
        loras: rows.map((row) => row.file),
        loraFacts: rows,
        deskDiscovery: [],
      });
    }
    return Promise.resolve({ ready: true });
  });
}

describe('StudioDesk artifact', () => {
  it('fills a Z-Image text encoder and VAE and skips CLIP-L', () => {
    const fills = supportFills(
      'z_image_turbo',
      'z_image_turbo_bf16.safetensors',
      {},
      ['clip_l.safetensors', 'qwen_3_4b.safetensors', 't5xxl_fp16.safetensors'],
      ['qwen_image_vae.safetensors', 'ae.safetensors'],
    );
    expect(fills['z_image_turbo/%MODEL_CLIP%']).toBe('qwen_3_4b.safetensors');
    expect(fills['z_image_turbo/%MODEL_VAE%']).toBe('ae.safetensors');
  });

  it('shows the desk labels, collapsed advanced, and the graph sheet', () => {
    render({ backend: 'comfyui' });
    const text = container.textContent ?? '';
    expect(text).toContain('Freeform');
    expect(text).toContain('Character');
    expect(text).toContain('Your persona');
    expect(text).toContain('Write it for me');
    expect(text).toContain('Start from a picture — optional. A reference here varies the Create model. It does not switch you to Edit.');
    expect(text).toContain('Expression pack');
    expect(text).toContain('Pack uses this Create model to vary the portrait.');
    expect(text).toContain('make a new portrait');
    expect(text).toContain('change this portrait');
    expect(text).toContain('Change graph');
    expect(text).toContain('Get a model from CivitAI');
    expect(text).toContain('Get a LoRA from CivitAI');
    expect(text).toContain('This graph also loads');
    expect(text).toContain('These files do not set the LoRA family. The text encoder can be Qwen while the model is Z-Image.');
    expect(text).toContain('Advanced ▸');
    expect(text).toContain('8 steps · cfg 1 · euler · simple');
    expect(container.querySelector('[aria-label="Steps"]')).toBeNull();
    expect(text).not.toContain('Model search');
    expect(text).not.toContain('CivitAI sign-in');

    act(() => button('Advanced ▸ 8 steps · cfg 1 · euler · simple')?.click());
    expect(container.textContent).toContain('Advanced ▾');
    expect(container.textContent).toContain('Change graph');
    expect(container.textContent).not.toContain('Advanced ▸');
    expect(container.querySelector('[aria-label="Steps"]')).not.toBeNull();
    expect(container.querySelector('[aria-label="CFG"]')).not.toBeNull();
    expect(container.querySelector('[aria-label="Sampler"]')).not.toBeNull();
    expect(container.querySelector('[aria-label="Scheduler"]')).not.toBeNull();
    expect(container.querySelector('[aria-label="Seed"]')).toBeNull();

    act(() => button('512×512')?.click());
    expect(container.textContent).toContain('Sends 512×512. Each side snaps to a multiple of 64, from 256 to 2048.');

    const width = container.querySelector('[aria-label="Width"]') as HTMLInputElement;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    act(() => {
      setter?.call(width, '300');
      width.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
    });
    expect(container.textContent).toContain(
      'Sends 320×512. Each side snaps to a multiple of 64, from 256 to 2048.',
    );
    expect((container.querySelector('[aria-label="Width"]') as HTMLInputElement).value).toBe('320');
    expect((container.querySelector('[aria-label="Height"]') as HTMLInputElement).value).toBe('512');

    act(() => button('Change graph')?.click());
    expect(container.textContent).toContain('Change graph — Create');
    expect(container.textContent).toContain('Drop a ComfyUI graph, or an image that has one saved inside it.');
    expect(container.textContent).toContain('Z-Image Turbo');
    expect(container.textContent).toContain('Text to image graphs');
    expect(container.textContent).toContain('Qwen-Image');
    expect(container.textContent).toContain('SD / SDXL');
    expect(container.textContent).toContain('Flux');
    expect(container.textContent).toContain('Text to image · z_image_turbo');
    expect(container.textContent).toContain('Text to image · flux');
    expect(container.textContent).toContain('Text to image · qwen_image');
    expect(container.textContent).toContain('Text to image · sd');
    expect(container.textContent).toContain('JSON, or a PNG from Comfy’s Save.');
    expect(container.textContent).toContain('Choose file');
    expect(container.textContent).toContain('Workflow · Text to image · z_image_turbo');

    act(() => button('Change model')?.click());
    expect(container.textContent).toContain('Change model — Create');
    expect(container.querySelector('input[placeholder="Search families or files"]')).not.toBeNull();

    act(() => button('Add')?.click());
    expect(container.textContent).toContain('Matches this model');
    expect(container.textContent).toContain('Other bases');
    expect(container.textContent).not.toContain('Search LoRAs');

    act(() => button('Get a model from CivitAI')?.click());
    expect(container.textContent).not.toContain('On this computer');
    expect(container.textContent).toContain('Include adult models from civitai.red');
    expect(container.textContent).toContain('Flux.1 Kontext');
    expect(container.textContent).toContain('Flux.2 Klein 9B');
    expect(container.textContent).toContain('Qwen 2.1');
    expect(container.textContent).toContain('Qwen-Image, 2512, and Image Edit');
    expect(container.textContent).not.toContain('Wan Video');
    expect(container.textContent).not.toContain('CivitAI sign-in');
    act(() => button('Get a LoRA from CivitAI')?.click());
    expect(container.textContent).not.toContain('On this computer');
    expect(container.textContent).toContain('Flux.1 Dev');
  });

  it('keeps a bare catalog filename likely until metadata says otherwise', async () => {
    vi.mocked(api.get).mockImplementation((url: string) => {
      if (String(url).includes('/api/image/studio/ready')) {
        return Promise.resolve({ ready: true, loraFacts: [] });
      }
      if (String(url).includes('comfy-catalog')) {
        return Promise.resolve({ loras: ['qwen_image_lora.safetensors'] });
      }
      return Promise.resolve({ ready: true });
    });
    render({
      backend: 'comfyui',
      workflowId: 'z_image_turbo',
      modelChoices: { 'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors' },
      loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('likely');
    expect(container.textContent).not.toContain('Use anyway');
    expect(button('Generate')?.hasAttribute('disabled')).toBe(false);
  });

  it('keeps Generate off for a metadata clash until Use anyway', async () => {
    mockReadyFacts([{ file: 'qwen_image_lora.safetensors', family: 'qwen', meta: true }]);
    render({
      loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('other base');
    expect(container.textContent).toContain('Generate stays off until you pick a matching LoRA or press Use anyway.');
    expect(container.textContent).toContain('Not ready — LoRA architecture does not match z_image_turbo_bf16.safetensors.');
    expect(container.textContent).not.toContain('Change graph');
    expect(button('Generate')?.hasAttribute('disabled')).toBe(true);
    act(() => button('Use anyway')?.click());
    expect(button('Generate')?.hasAttribute('disabled')).toBe(false);
  });

  it('hides the text encoder and VAE on Draw Things', () => {
    render({ backend: 'drawthings', workflowId: 'z_image_turbo' });
    expect(container.textContent).not.toContain('This graph also loads');
    expect(container.textContent).not.toContain('Change graph');
    expect(container.textContent).not.toContain('Text encoder');
    act(() => button('Advanced ▸ 8 steps · cfg 1 · euler · simple')?.click());
    const menu = container.querySelector('[aria-label="Draw Things sampler"]') as HTMLSelectElement;
    const labels = [...menu.options].map((option) => option.textContent);
    expect(labels).toContain('Euler a Trailing');
    expect(labels).toContain('DPM++ 2M Karras');
    expect(labels).toHaveLength(19);
  });

  it('leaves a name-only mismatch as likely', async () => {
    mockReadyFacts([{ file: 'qwen_image_lora.safetensors', family: 'qwen', meta: false }]);
    render({
      loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('likely');
    expect(container.textContent).not.toContain('other base');
    expect(button('Generate')?.hasAttribute('disabled')).toBe(false);
    expect(container.textContent).toContain('Ready to generate.');
  });

  it('moves a saved GGUF file off the checkpoint graph', async () => {
    const onSave = vi.fn();
    render({
      backend: 'comfyui',
      workflowId: 'sd',
      model: 'z_image_turbo_q8.gguf',
      onSave,
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(onSave).toHaveBeenCalledWith(expect.objectContaining({
      comfyCreateWorkflowId: 'z_image_turbo',
      comfyCreateModelChoices: expect.objectContaining({
        'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_q8.gguf',
      }),
    }));
  });

  it('writes a support Change into that VAE slot', async () => {
    vi.mocked(api.get).mockImplementation((url: string) => {
      if (String(url).includes('comfy-catalog')) {
        return Promise.resolve({
          vaes: ['ae.safetensors'],
          textEncoders: ['qwen_3_4b.safetensors'],
          deskDiscovery: ['z_image_turbo_bf16.safetensors'],
        });
      }
      return Promise.resolve({ ready: true });
    });
    const onSave = vi.fn();
    render({
      backend: 'comfyui',
      workflowId: 'z_image_turbo',
      model: 'z_image_turbo_bf16.safetensors',
      onSave,
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('Change graph');
    const change = [...container.querySelectorAll('button')].find(
      (item) => item.textContent === 'Change' && item.parentElement?.textContent?.startsWith('VAE'),
    );
    await act(async () => {
      change?.click();
      await Promise.resolve();
    });
    expect(button('ae.safetensors')).toBeTruthy();
    act(() => button('ae.safetensors')?.click());
    const patches = onSave.mock.calls.map((call) => call[0] as {
      comfyCreateModelChoices?: Record<string, string>;
    });
    expect(patches.some((patch) => patch.comfyCreateModelChoices?.['z_image_turbo/%MODEL_VAE%'] === 'ae.safetensors')).toBe(true);
    expect(patches.some((patch) => patch.comfyCreateModelChoices?.['z_image_turbo/%MODEL_DIFFUSION%'] === 'ae.safetensors')).toBe(false);
  });

  it('selects an other-base LoRA', async () => {
    mockReadyFacts([{ file: 'z-image-turbo-realism.safetensors', family: 'zImage', meta: true }]);
    const onSave = vi.fn();
    render({
      backend: 'comfyui',
      workflowId: 'qwen_image',
      modelChoices: { 'qwen_image/%MODEL_DIFFUSION%': 'qwen_image_bf16.safetensors' },
      onSave,
    });
    await act(async () => {
      await Promise.resolve();
    });
    act(() => button('Add')?.click());
    await act(async () => {
      await Promise.resolve();
    });
    const row = button('z-image-turbo-realism.safetensors') as HTMLButtonElement;
    expect(row.disabled).toBe(false);
    const other = [...container.querySelectorAll('p')].find((item) => item.textContent === 'Other bases');
    expect(other?.nextElementSibling?.textContent).toContain('z-image-turbo-realism.safetensors');
    act(() => row.click());
    expect(onSave).toHaveBeenCalledWith(expect.objectContaining({
      loras: expect.arrayContaining([
        expect.objectContaining({ file: 'z-image-turbo-realism.safetensors' }),
      ]),
    }));
  });

  it('shows the clash on the image page from the ready response', async () => {
    vi.mocked(api.get).mockImplementation((url: string) => {
      if (url === '/api/image/config') {
        return Promise.resolve({
          backend: 'remote',
          isConfigured: true,
          size: '1024x1024',
          style: '',
          model: 'z_image_turbo_bf16.safetensors',
          negativePrompt: '',
          steps: 8,
          cfgScale: 1,
          sampler: 'euler',
          scheduler: 'simple',
          loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
          localUrl: 'http://127.0.0.1:7860',
          comfyUrl: 'http://127.0.0.1:8188',
          promptReview: false,
          drawThingsHost: '127.0.0.1',
          drawThingsPort: 7859,
          remoteApiUrl: 'https://example.test',
          remoteModelName: '',
          hasApiKey: false,
          comfyCreateWorkflowId: 'z_image_turbo',
        });
      }
      if (url.includes('/api/image/expression-pack')) {
        return Promise.resolve({ running: false, filenames: [], verdicts: [] });
      }
      if (url.includes('/api/auth/state')) return Promise.resolve({ totpEnabled: false });
      if (url.includes('/api/image/studio/ready')) {
        return Promise.resolve({
          ready: false,
          kind: 'loraMismatch',
          blockedLora: 'qwen_image_lora.safetensors',
          primary: 'z_image_turbo_bf16.safetensors',
          loraFamily: 'zImage',
          loraFacts: [{ file: 'qwen_image_lora.safetensors', family: 'qwen', meta: true }],
        });
      }
      return Promise.resolve({ ready: true });
    });
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root.render(createElement(ImageGen, { onError: () => {} }));
      await Promise.resolve();
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(container.textContent).toContain('other base');
    expect(container.textContent).toContain('Use anyway');
  });
});
