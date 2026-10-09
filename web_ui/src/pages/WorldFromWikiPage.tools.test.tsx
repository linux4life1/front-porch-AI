// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Wiki on the phone reads the host's answer to "can this model use
// tools?" (chat's own tool check, the sidebar's Tool calling pill) and says in
// plain words why Scout is locked: still checking, not running yet, or tested
// and failed. Only a passed check unlocks Scout. The host's side of this is
// pinned in test/services/web/world_from_wiki_tools_gate_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

import { WorldFromWikiPage } from './WorldFromWikiPage';

let container: HTMLDivElement;
let root: Root;

async function show(toolsGate: string) {
  get.mockResolvedValue({
    available: true,
    toolsAdvertised: toolsGate === 'ready',
    toolsGate,
    savedWikis: ['https://example.fandom.com'],
  });
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldFromWikiPage)));
  });
}

const scout = () =>
  Array.from(container.querySelectorAll('button')).find((b) =>
    b.textContent?.includes('Scout wiki'),
  )!;
const copy = () => container.querySelector('[data-testid="world-from-wiki-tools-copy"]');
const retest = () =>
  container.querySelector<HTMLButtonElement>('[data-testid="world-from-wiki-tools-retest"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('World from Wiki tools gate on the phone', () => {
  it('says it is checking while the host asks the model', async () => {
    await show('checking');
    expect(copy()?.textContent).toContain('Checking whether this model can use tools');
    expect(scout().disabled).toBe(true);
    expect(retest()).toBeNull();
  });

  it('says the model has to be running, and where to start it', async () => {
    await show('notRunning');
    expect(copy()?.textContent).toContain('has to be running first');
    expect(copy()?.textContent).toContain('Models page');
    expect(scout().disabled).toBe(true);
  });

  it('says a tested model failed and cannot be used, apart from "not tested"', async () => {
    await show('failed');
    const text = copy()?.textContent ?? '';
    expect(text).toContain("was tested and didn't answer the tool-calling check");
    expect(text).toContain("can't be used for World from Wiki");
    expect(text).toContain('Pick a different model');
    expect(text).not.toContain('Checking');
    expect(text).not.toContain('running first');
    expect(scout().disabled).toBe(true);
    expect(retest()).toBeNull();
  });

  it('offers Check now when the running model was never asked', async () => {
    await show('notChecked');
    expect(copy()?.textContent).toContain("hasn't been checked for tools yet");
    post.mockResolvedValue({ state: 'supported' });
    await act(async () => {
      retest()!.click();
    });
    expect(post).toHaveBeenCalledWith('/api/worlds/from-wiki/tool-test');
  });

  it('unlocks Scout with no explanation once the check passed', async () => {
    await show('ready');
    expect(copy()).toBeNull();
    expect(scout().disabled).toBe(false);
  });
});
