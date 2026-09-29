// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { StudioDesk, type StudioDeskProps } from './StudioDesk';

vi.mock('../../api/client', () => ({
  api: {
    get: vi.fn((url: string) => {
      if (url.includes('/api/image/studio/ready')) {
        return Promise.resolve({
          ready: true,
          reachable: true,
          diffusionCount: 2,
          loraCount: 1,
        });
      }
      if (url.includes('/api/image/local-catalog')) {
        return Promise.resolve({
          models: ['qwen_image.safetensors', 'flux_dev.safetensors'],
          loras: ['detail.safetensors'],
          loraFacts: [{ file: 'detail.safetensors', family: 'qwen', meta: true }],
          diffusionCount: 2,
          loraCount: 1,
        });
      }
      return Promise.resolve({});
    }),
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
  backend: 'drawthings',
  model: 'qwen_image.safetensors',
  size: '1024x1024',
  steps: 8,
  sampler: 'euler',
  workflowId: 'qwen_image',
  cfg: 1,
  scheduler: 'simple',
  comfyUrl: 'http://127.0.0.1:8188',
  localUrl: 'http://127.0.0.1:7860',
  drawThingsHost: '127.0.0.1',
  remoteUrl: '',
  onSave: () => {},
};

describe('Draw Things desk', () => {
  it('shows the diffusion count and lists LoRAs', async () => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    act(() => {
      root.render(createElement(StudioDesk, base));
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('Reachable · 2 diffusion files · 1 LoRAs');
    const add = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Add');
    act(() => add?.click());
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('detail.safetensors');
    expect(api.get).toHaveBeenCalledWith(
      '/api/image/local-catalog?model=qwen_image.safetensors',
    );
  });
});
