// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatComposer } from './ChatComposer';

let container: HTMLDivElement;
let root: Root;

function render(apiReady: boolean) {
  act(() => {
    root.render(
      createElement(ChatComposer, {
        onSend: vi.fn(),
        onStop: vi.fn(),
        isGenerating: false,
        canMic: false,
        apiReady,
      }),
    );
  });
}

function area(): HTMLTextAreaElement {
  return container.querySelector('textarea')!;
}

describe('ChatComposer placeholder', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('shows No API connection when the host LLM is down', () => {
    render(false);
    expect(area().placeholder).toBe('No API connection');
  });

  it('offers an Attach photo control', () => {
    render(true);
    expect(
      container.querySelector('button[aria-label="Attach photo"]'),
    ).not.toBeNull();
    expect(container.querySelector('input[type="file"][accept="image/*"]')).not.toBeNull();
  });

  it('restores the normal placeholder when the connection recovers', () => {
    render(false);
    expect(area().placeholder).toBe('No API connection');
    render(true);
    expect(area().placeholder).toBe('Message…');
  });
});
