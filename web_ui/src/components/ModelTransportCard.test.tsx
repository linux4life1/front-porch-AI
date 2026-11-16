// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '../api/client';
import { ModelTransportCard } from './ModelTransportCard';

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
  vi.restoreAllMocks();
});

describe('ModelTransportCard (Engine & Display Options)', () => {
  it('renders both Model transport and Display Output tiles and saves Display Output settings', async () => {
    vi.spyOn(api, 'get').mockResolvedValue({
      realism: { preferTextEvals: false },
      displayBufferEnabled: false,
      targetDisplayTps: 30,
      bufferDurationSeconds: 3,
    });
    const postSpy = vi.spyOn(api, 'post').mockResolvedValue({});

    await act(async () => {
      root.render(createElement(ModelTransportCard));
    });
    await act(async () => {
      await Promise.resolve();
    });

    expect(container.textContent).toContain('Engine & Display Options');
    expect(container.textContent).toContain('Model transport');
    expect(container.textContent).toContain('Native tool calling');
    expect(container.textContent).toContain('Display Output');
    expect(container.textContent).toContain('Smooth Output Buffer');
    expect(container.textContent).not.toContain('Target Display Speed (t/s)');

    const bufferSwitch = container.querySelector<HTMLInputElement>(
      'input[aria-label="Smooth Output Buffer"]',
    )!;
    await act(async () => {
      bufferSwitch.click();
    });

    expect(postSpy).toHaveBeenCalledWith('/api/settings', { displayBufferEnabled: true });
    expect(container.textContent).toContain('Target Display Speed (t/s)');
    expect(container.textContent).toContain('Buffer Duration (seconds)');
  });
});
