// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: async () => ({
      models: [
        { id: 'hidream', name: 'Hidream', label: 'Hidream · Pro', isPaid: false },
        { id: 'flux-2-pro', name: 'FLUX.2 Pro', label: 'FLUX.2 Pro · paid', isPaid: true },
      ],
    }),
    post: async () => ({}),
  },
}));

const { ImageRemoteFields } = await import('./ImageRemoteFields');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ImageRemoteFields', () => {
  it('enables Nano when the vault has a key and disables OpenRouter', async () => {
    let host = '';
    await act(async () => {
      root.render(
        createElement(ImageRemoteFields, {
          selectedHostId: 'nano',
          hosts: [
            { id: 'nano', label: 'Nano-GPT', url: 'https://nano-gpt.com/api/v1', hasKey: true },
            {
              id: 'openrouter',
              label: 'OpenRouter',
              url: 'https://openrouter.ai/api/v1',
              hasKey: false,
            },
          ],
          modelId: '',
          hasApiKey: true,
          remoteApiUrl: 'https://nano-gpt.com/api/v1',
          onHost: (id: string) => {
            host = id;
          },
          onModel: () => {},
          onError: () => {},
        }),
      );
    });
    await act(async () => {
      await Promise.resolve();
    });

    const nano = container.querySelector(
      '[data-testid="image-remote-host-nano"]',
    ) as HTMLButtonElement;
    const or = container.querySelector(
      '[data-testid="image-remote-host-openrouter"]',
    ) as HTMLButtonElement;
    expect(nano.disabled).toBe(false);
    expect(or.disabled).toBe(true);
    expect(container.textContent).toContain('Settings → Backend');
    expect(container.textContent).toContain('nano-gpt.com');

    nano.click();
    expect(host).toBe('nano');
  });

  it('search filters the remote image list and shows Pro/paid labels', async () => {
    let model = '';
    await act(async () => {
      root.render(
        createElement(ImageRemoteFields, {
          selectedHostId: 'nano',
          hosts: [
            { id: 'nano', label: 'Nano-GPT', url: 'https://nano-gpt.com/api/v1', hasKey: true },
          ],
          modelId: '',
          hasApiKey: true,
          remoteApiUrl: 'https://nano-gpt.com/api/v1',
          onHost: () => {},
          onModel: (id: string) => {
            model = id;
          },
          onError: () => {},
        }),
      );
    });
    await act(async () => {
      await Promise.resolve();
    });

    const trigger = container.querySelector(
      '[data-testid="image-remote-model-search"]',
    ) as HTMLButtonElement;
    await act(async () => {
      trigger.click();
    });
    expect(container.textContent).toContain('Hidream · Pro');
    expect(container.textContent).toContain('FLUX.2 Pro · paid');

    const filter = container.querySelector('.mp-filter') as HTMLInputElement;
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )!.set!;
      setter.call(filter, 'hidream');
      filter.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const labels = Array.from(container.querySelectorAll('.mp-option')).map(
      (el) => el.textContent,
    );
    expect(labels.some((t) => t?.includes('Hidream · Pro'))).toBe(true);
    expect(labels.some((t) => t?.includes('FLUX.2 Pro · paid'))).toBe(false);

    const option = Array.from(container.querySelectorAll('.mp-option')).find((el) =>
      el.textContent?.includes('Hidream'),
    ) as HTMLButtonElement;
    await act(async () => {
      option.click();
    });
    expect(model).toBe('hidream');
  });
});
