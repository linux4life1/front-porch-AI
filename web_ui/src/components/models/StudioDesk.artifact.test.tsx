// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { StudioDesk, type StudioDeskProps } from './StudioDesk';

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

describe('StudioDesk artifact', () => {
  it('shows the desk labels, collapsed advanced, and the graph sheet', () => {
    render();
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
    expect(text).not.toContain('Change graph');
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
    expect(container.textContent).toContain('JSON, or a PNG from Comfy’s Save.');
    expect(container.textContent).toContain('Choose file');
    expect(container.textContent).toContain('Workflow · Text to image · z_image_turbo');

    act(() => button('Change model')?.click());
    expect(container.textContent).toContain('Change model — Create');
    expect(container.querySelector('input[placeholder="Search families or files"]')).not.toBeNull();

    act(() => button('Add')?.click());
    expect(container.textContent).toContain('Matches this model');
    expect(container.textContent).toContain('Other bases');

    act(() => button('Get a model from CivitAI')?.click());
    expect(container.textContent).toContain('On this computer');
    expect(container.textContent).toContain('Include adult models from civitai.red');
    expect(container.textContent).not.toContain('CivitAI sign-in');
  });

  it('keeps Generate off for a metadata clash until Use anyway', async () => {
    render({
      loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
      loraFacts: { 'qwen_image_lora.safetensors': { family: 'qwen', meta: true } },
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('other base');
    expect(container.textContent).toContain('Generate stays off until you pick a matching LoRA or press Use anyway.');
    expect(container.textContent).toContain('Not ready — LoRA architecture does not match z_image_turbo_bf16.safetensors.');
    expect(button('Generate')?.hasAttribute('disabled')).toBe(true);
    act(() => button('Use anyway')?.click());
    expect(button('Generate')?.hasAttribute('disabled')).toBe(false);
  });

  it('hides the text encoder and VAE on Draw Things', () => {
    render({ backend: 'drawthings', workflowId: 'z_image_turbo' });
    expect(container.textContent).not.toContain('This graph also loads');
    expect(container.textContent).not.toContain('Text encoder');
    act(() => button('Advanced ▸ 8 steps · cfg 1 · euler · simple')?.click());
    const menu = container.querySelector('[aria-label="Draw Things sampler"]') as HTMLSelectElement;
    const labels = [...menu.options].map((option) => option.textContent);
    expect(labels).toContain('Euler a Trailing');
    expect(labels).toContain('DPM++ 2M Karras');
    expect(labels).toHaveLength(19);
  });

  it('leaves a name-only mismatch as likely', async () => {
    render({
      loras: [{ file: 'qwen_image_lora.safetensors', weight: 0.8 }],
      loraFacts: { 'qwen_image_lora.safetensors': { family: 'qwen', meta: false } },
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('likely');
    expect(container.textContent).not.toContain('other base');
    expect(button('Generate')?.hasAttribute('disabled')).toBe(false);
    expect(container.textContent).toContain('Ready to generate.');
  });
});
