// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The tool-calling pill says when its answer was kept from an earlier run
// instead of asked just now, and that a click asks again; the desktop sidebar
// says the same. A host that does not send the flag (an older desktop) gets
// the usual line. Renders the real component; the host's answers are supplied.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { post } = vi.hoisted(() => ({ post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { post } }));

import { ToolCallingPill } from './ToolCallingPill';

const SAVED = 'Saved from an earlier test. Click to ask again.';

let container: HTMLDivElement;
let root: Root;

async function show(support: Record<string, unknown>) {
  await act(async () => {
    root.render(createElement(ToolCallingPill, { support: support as never }));
  });
}

const label = () => container.querySelector('strong')?.textContent;
const detail = () => container.querySelector('.muted')?.textContent;

async function click() {
  await act(async () => {
    container.querySelector('button')!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Tool calling pill: a kept answer', () => {
  it('a kept "yes" says it is saved, and a click shows a fresh answer', async () => {
    await show({ state: 'supported', testing: false, saved: true });
    expect(label()).toBe('Tool calling: supported');
    expect(detail()).toBe(SAVED);

    post.mockResolvedValue({ state: 'supported', testing: false, saved: false });
    await click();

    expect(post).toHaveBeenCalledWith('/api/chat/tool-test', {});
    expect(label()).toBe('Tool calling: supported');
    expect(detail()).toBe('Realism, Journal & Growth use native tool calls');
  });

  it('a kept "no" says it is saved too, and a click shows a fresh answer', async () => {
    await show({ state: 'unsupported', testing: false, saved: true });
    expect(label()).toBe('Tool calling: not supported');
    expect(detail()).toBe(SAVED);

    post.mockResolvedValue({ state: 'unsupported', testing: false, saved: false });
    await click();

    expect(label()).toBe('Tool calling: not supported');
    expect(detail()).toBe('Using the text fallback — still works');
  });

  it('a host that does not say gets the usual line', async () => {
    await show({ state: 'supported', testing: false });
    expect(detail()).toBe('Realism, Journal & Growth use native tool calls');
    await show({ state: 'unsupported', testing: false });
    expect(detail()).toBe('Using the text fallback — still works');
  });

  it('does not hide the notes that matter more', async () => {
    await show({ state: 'supported', testing: false, saved: true, preferText: true });
    expect(detail()).toBe('You turned native tool calls off in Generation settings');
    await show({ state: 'supported', testing: false, saved: true, paused: true });
    expect(detail()).toBe('Empty answers this session — click to retry');
    await show({ state: 'supported', testing: true, saved: true });
    expect(detail()).toBe('Asking the model for a tool call');
  });
});
