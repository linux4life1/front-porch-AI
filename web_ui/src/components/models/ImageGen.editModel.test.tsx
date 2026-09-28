// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { api } from '../../api/client';
import { ImageGen } from './ImageGen';

vi.mock('../../api/client', () => ({
  api: {
    get: vi.fn((url: string) => {
      if (url === '/api/image/config') {
        return Promise.resolve({
          backend: 'a1111',
          isConfigured: true,
          size: '1024x1024',
          style: '',
          model: 'create.safetensors',
          editModel: 'edit-portrait.safetensors',
          negativePrompt: '',
          steps: 20,
          cfgScale: 7,
          sampler: 'euler',
          scheduler: 'normal',
          localUrl: 'http://127.0.0.1:7860',
          comfyUrl: 'http://127.0.0.1:8188',
          promptReview: false,
          drawThingsHost: '127.0.0.1',
          drawThingsPort: 7859,
          remoteApiUrl: '',
          remoteModelName: '',
          hasApiKey: false,
        });
      }
      if (url.includes('/api/image/expression-pack')) {
        return Promise.resolve({ running: false, filenames: [], verdicts: [] });
      }
      return Promise.resolve({ ready: false });
    }),
    post: vi.fn().mockResolvedValue({}),
  },
  ApiError: class ApiError extends Error {},
}));

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
});

describe('ImageGen edit model', () => {
  it('shows a saved Automatic1111 edit model on the edit tab', async () => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    await act(async () => {
      root.render(createElement(ImageGen, { onError: () => {} }));
      await Promise.resolve();
      await Promise.resolve();
    });
    const edit = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Edit');
    act(() => edit?.click());
    expect(container.textContent).toContain('edit-portrait.safetensors');
    expect(container.textContent).not.toContain('No model chosen');
    expect(api.get).toHaveBeenCalledWith('/api/image/config');
  });
});
