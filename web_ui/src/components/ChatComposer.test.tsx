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

  it('keeps a line typed while a reply streams when Enter is pressed', async () => {
    const onSend = vi.fn();
    const composer = (isGenerating: boolean) =>
      createElement(ChatComposer, { onSend, onStop: vi.fn(), isGenerating, canMic: false });
    act(() => root.render(composer(true)));
    const ta = area();
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
    await act(async () => {
      setter.call(ta, '/narrate a storm rolls in');
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const enter = () =>
      ta.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await act(async () => enter());
    expect(onSend).not.toHaveBeenCalled();
    expect(area().value).toBe('/narrate a storm rolls in');

    act(() => root.render(composer(false)));
    await act(async () => enter());
    expect(onSend).toHaveBeenCalledWith('/narrate a storm rolls in');
  });

  it('offers /skip in the command list, like the desktop', async () => {
    render(true);
    const ta = area();
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
    await act(async () => {
      setter.call(ta, '/');
      ta.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const rows = [...container.querySelectorAll('.cheatsheet-row')].map((r) => r.textContent ?? '');
    const skip = rows.find((r) => r.startsWith('/skip'));
    expect(skip).toContain('<8h | 2d | morning | 07:30>');
  });
});
