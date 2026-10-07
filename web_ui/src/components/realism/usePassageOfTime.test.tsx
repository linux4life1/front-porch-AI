// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// usePassageOfTime reads Porch Life's Passage of Time once, then follows it
// live: the server broadcasts `settings_changed` whenever a setting is written
// (on the desktop or another browser) and the hook refetches, so a page left
// open does not keep its first read (review finding, Needs v2).

import { act } from 'react';
import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Listener = (e: { event: string }) => void;
let listener: Listener | null = null;
let passage = true;
let reads = 0;

vi.mock('../../api/client', () => ({
  api: {
    get: async () => {
      reads += 1;
      return { realism: { passageOfTimeDefault: passage } };
    },
  },
}));

vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: Listener) {
      listener = cb;
    }
    connect() {}
    close() {
      listener = null;
    }
  },
}));

const { usePassageOfTime } = await import('./usePassageOfTime');

let latest: boolean | null = null;
function Probe() {
  latest = usePassageOfTime();
  return null;
}

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  passage = true;
  reads = 0;
  latest = null;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const flush = async () => {
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
};

describe('usePassageOfTime', () => {
  it('reads the switch once on mount', async () => {
    passage = false;
    await act(async () => root.render(createElement(Probe)));
    await flush();
    expect(reads).toBe(1);
    expect(latest).toBe(false);
  });

  it('refetches when the server says a setting changed', async () => {
    await act(async () => root.render(createElement(Probe)));
    await flush();
    expect(latest).toBe(true);

    passage = false;
    await act(async () => listener?.({ event: 'settings_changed' }));
    await flush();
    expect(reads).toBe(2);
    expect(latest).toBe(false);

    passage = true;
    await act(async () => listener?.({ event: 'connected' }));
    await flush();
    expect(latest).toBe(true);
  });

  it('ignores unrelated events', async () => {
    await act(async () => root.render(createElement(Probe)));
    await flush();
    await act(async () => listener?.({ event: 'chat_updated' }));
    await flush();
    expect(reads).toBe(1);
  });
});
