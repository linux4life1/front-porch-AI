// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api, ApiError } from '../../api/client';
import { StudioDesk, type StudioDeskProps } from './StudioDesk';

vi.mock('../../api/client', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../api/client')>();
  return {
    ...actual,
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
  };
});

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
  vi.mocked(api.post).mockReset();
  vi.mocked(api.post).mockResolvedValue({ downloaded: true });
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

function render(extra: Partial<StudioDeskProps> = {}) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(StudioDesk, { ...base, ...extra }));
  });
}

async function choose(label: string, extra: Partial<StudioDeskProps> = {}) {
  render(extra);
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
    await Promise.resolve();
    await Promise.resolve();
  });
}

describe('StudioDesk CivitAI download', () => {
  it('posts a model row to the download relay and does not send a key', async () => {
    await choose('Get a model from CivitAI');
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
    await choose('Get a LoRA from CivitAI');
    expect(api.post).toHaveBeenCalledWith(
      '/api/image/civitai/download',
      expect.objectContaining({ versionId: 42, lora: true, filename: 'portrait.safetensors' }),
    );
  });

  it('says the computer is downloading when the row is tapped', async () => {
    let finish: (value: unknown) => void = () => {};
    vi.mocked(api.post).mockImplementation((url: string) => {
      if (url === '/api/image/civitai/download') {
        return new Promise((resolve) => {
          finish = resolve;
        });
      }
      return Promise.resolve({ accept: false });
    });
    const onSave = vi.fn();
    await choose('Get a model from CivitAI', { onSave });
    expect(container.textContent).toContain('Downloading on your computer…');
    expect(container.textContent).not.toContain('Saved to your models folder');
    await act(async () => {
      finish({ downloaded: true });
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(container.textContent).toContain(
      'Saved to your models folder on this computer. Pick it in Model search.',
    );
    expect(container.textContent).not.toContain('Downloading on your computer…');
    expect(onSave).not.toHaveBeenCalled();
  });

  it('selects a Comfy file the computer says the workflow can load', async () => {
    const onSave = vi.fn();
    vi.mocked(api.post).mockImplementation((url: string) => {
      if (url === '/api/image/studio/installed') {
        return Promise.resolve({
          accept: true,
          kind: 'comfy',
          token: '%MODEL_DIFFUSION%',
          workflowId: 'z_image_turbo',
        });
      }
      return Promise.resolve({ downloaded: true });
    });
    await choose('Get a model from CivitAI', { onSave, workflowId: 'z_image_turbo' });
    expect(api.post).toHaveBeenCalledWith('/api/image/studio/installed', {
      filename: 'portrait.safetensors',
      lora: false,
      workflowId: 'sd',
    });
    expect(onSave).toHaveBeenCalledWith({
      comfyCreateWorkflowId: 'z_image_turbo',
      comfyCreateModelChoices: {
        'z_image_turbo/%MODEL_DIFFUSION%': 'portrait.safetensors',
      },
    });
    expect(container.textContent).toContain('Saved to your models folder on this computer.');
    expect(container.textContent).not.toContain('Pick it in Model search');
  });

  it('tells an Automatic1111 LoRA that the file is in the Lora folder', async () => {
    vi.mocked(api.post).mockImplementation((url: string) => {
      if (url === '/api/image/studio/installed') {
        return Promise.resolve({ accept: false });
      }
      return Promise.resolve({ downloaded: true });
    });
    await choose('Get a LoRA from CivitAI', { backend: 'a1111' });
    expect(container.textContent).toContain('It is in the Lora folder.');
    expect(container.textContent).not.toContain('Pick it in LoRA search');
  });

  it('selects an Automatic1111 file into the model slot', async () => {
    const onSave = vi.fn();
    vi.mocked(api.post).mockImplementation((url: string) => {
      if (url === '/api/image/studio/installed') {
        return Promise.resolve({ accept: true, kind: 'slot' });
      }
      return Promise.resolve({ downloaded: true });
    });
    await choose('Get a model from CivitAI', { onSave, backend: 'a1111' });
    expect(onSave).toHaveBeenCalledWith({ model: 'portrait.safetensors' });
  });

  it('shows the computer refusal instead of a generic failure', async () => {
    vi.mocked(api.post).mockRejectedValueOnce(
      new ApiError(400, 'Pick your models folder on this computer first', {}),
    );
    await choose('Get a model from CivitAI');
    expect(container.textContent).toContain(
      'Pick your models folder on this computer first',
    );
    expect(container.textContent).not.toContain('CivitAI download failed.');
  });

  it('hides a raw error page instead of printing it', async () => {
    vi.mocked(api.post).mockRejectedValueOnce(
      new ApiError(502, '<html><body>bad gateway</body></html>', {}),
    );
    await choose('Get a model from CivitAI');
    expect(container.textContent).toContain('CivitAI download failed.');
    expect(container.textContent).not.toContain('<html>');
  });

  it('says the download failed when the relay rejects', async () => {
    vi.mocked(api.post).mockRejectedValueOnce(new Error('nope'));
    await choose('Get a model from CivitAI');
    expect(container.textContent).toContain('CivitAI download failed.');
  });
});
