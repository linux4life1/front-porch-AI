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
});

const desk: StudioDeskProps = {
  backend: 'comfyui',
  model: 'z_image_turbo_bf16.safetensors',
  size: '1024x1024',
  steps: 8,
  sampler: 'euler',
  workflowId: 'z_image_turbo',
  modelChoices: {
    'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
  },
  cfg: 1,
  scheduler: 'simple',
  comfyUrl: 'http://127.0.0.1:8189',
  localUrl: 'http://127.0.0.1:7860',
  drawThingsHost: '127.0.0.1',
  remoteUrl: 'https://example.test',
  onSave: () => {},
};

function button(label: string) {
  return [...container.querySelectorAll('button')].find((b) => b.textContent === label);
}

describe('Change graph and the loaded model', () => {
  it('hides premade graphs that cannot load the selected file', async () => {
    vi.mocked(api.get).mockImplementation((url: string) => {
      if (String(url).includes('comfy-catalog')) {
        return Promise.resolve({
          graphs: [
            { id: 'z_image_turbo', title: 'Z-Image Turbo', detail: 'Text to image · z_image_turbo', group: 'Text to image graphs' },
            { id: 'flux', title: 'Flux', detail: 'Text to image · flux', group: 'Text to image graphs' },
            { id: 'qwen_image', title: 'Qwen-Image', detail: 'Text to image · qwen_image', group: 'Text to image graphs' },
            { id: 'sd', title: 'SD / SDXL / Pony', detail: 'Text to image · sd', group: 'Text to image graphs' },
            { id: 'comfy:default:flux_schnell', title: 'Flux Schnell', detail: 'Text to image · comfy:default:flux_schnell', group: 'From this Comfy' },
            { id: 'comfy:userdata:evening_shift', title: 'evening shift', detail: 'Text to image · comfy:userdata:evening_shift', group: 'Saved on this Comfy' },
          ],
        });
      }
      return Promise.resolve({ ready: true });
    });
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    act(() => {
      root.render(createElement(StudioDesk, desk));
    });
    await act(async () => {
      button('Change graph')?.click();
      await Promise.resolve();
    });
    const text = container.textContent ?? '';
    expect(text).toContain('Z-Image Turbo');
    expect(text).toContain('evening shift');
    expect(text).toContain('Text to image · z_image_turbo');
    expect(text).not.toContain('Flux');
    expect(text).not.toContain('Qwen-Image');
    expect(text).not.toContain('SD / SDXL');
    expect(text).not.toContain('Text to image · flux');
    expect(text).not.toContain('Text to image · qwen_image');
    expect(text).not.toContain('Text to image · sd');
  });
});
