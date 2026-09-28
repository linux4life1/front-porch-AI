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
      if (url.includes('/api/image/civitai/search')) {
        return Promise.resolve({
          items: [
            {
              filename: 'portrait.safetensors',
              versionId: 42,
              type: 'Checkpoint',
              adult: false,
            },
          ],
          needsCredential: false,
        });
      }
      if (url.includes('/api/image/studio/ready')) {
        return Promise.resolve({ ready: false });
      }
      return Promise.resolve({});
    }),
    post: vi.fn().mockResolvedValue({ downloaded: true }),
  },
}));

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
  vi.mocked(api.post).mockClear();
});

const base: StudioDeskProps = {
  backend: 'comfyui',
  model: '',
  size: '1024x1024',
  steps: 20,
  sampler: 'euler',
  workflowId: 'sd',
  comfyUrl: 'http://127.0.0.1:8188',
  localUrl: 'http://127.0.0.1:7860',
  drawThingsHost: '127.0.0.1',
  remoteUrl: '',
  onSave: () => {},
};

function render() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(StudioDesk, base));
  });
}

async function choose(label: string) {
  render();
  const open = [...container.querySelectorAll('button')].find((b) => b.textContent === label);
  act(() => open?.click());
  const box = container.querySelector('input[aria-label="Search"]') as HTMLInputElement;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
  act(() => {
    setter?.call(box, 'portrait');
    box.dispatchEvent(new Event('input', { bubbles: true }));
  });
  const search = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Search');
  act(() => search?.click());
  await act(async () => {
    await Promise.resolve();
  });
  const row = [...container.querySelectorAll('button')].find((b) => b.textContent === 'portrait.safetensors');
  act(() => row?.click());
  await act(async () => {
    await Promise.resolve();
  });
}

describe('StudioDesk CivitAI download', () => {
  it('posts a model row to the download relay and does not send a key', async () => {
    await choose('Get a model');
    expect(api.post).toHaveBeenCalledWith('/api/image/civitai/download', {
      versionId: 42,
      backend: 'comfyui',
      adult: false,
      filename: 'portrait.safetensors',
      type: 'Checkpoint',
      lora: false,
    });
    const body = vi.mocked(api.post).mock.calls.find((call) => call[0] === '/api/image/civitai/download')?.[1] as
      | Record<string, unknown>
      | undefined;
    expect(body).not.toHaveProperty('token');
    expect(body).not.toHaveProperty('key');
    expect(JSON.stringify(body)).not.toContain('Authorization');
  });

  it('posts a LoRA row with the lora flag', async () => {
    await choose('Get a LoRA');
    expect(api.post).toHaveBeenCalledWith(
      '/api/image/civitai/download',
      expect.objectContaining({ versionId: 42, lora: true, filename: 'portrait.safetensors' }),
    );
  });
});
