// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 4 (docs/design/one-chat-ux.md): group memory is per member. The desktop
// Memory leaf now shows in a group; the PWA's Memory section already did, and
// must keep showing, with the same switch and count. In a group the host
// answers those two with the GROUP's own gate (`memory.ragScope: 'group'`), so
// this section posts them exactly as in a 1:1 and the host routes them. Its
// routing is pinned on the host side (member_switches_facade_test.dart).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get: () => new Promise(() => {}), post: () => new Promise(() => {}) },
}));

const { ChatToolsMemory } = await import('./ChatToolsMemory');

let container: HTMLDivElement;
let root: Root;

function state(ragScope: 'group' | 'global') {
  return {
    memory: {
      ragEnabled: true,
      ragScope,
      ragRetrievalCount: 4,
      ragWindowSize: 5,
      journalEnabled: true,
      journalInterval: 10,
      growthEnabled: false,
      growthInterval: 10,
      growthReviewFirst: false,
      embedding: { available: true },
    },
    summary: { text: '', paused: false, isGenerating: false, lastIndex: 0 },
  };
}

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

describe('the Memory section', () => {
  for (const scope of ['group', 'global'] as const) {
    it(`shows the same switch and count in a ${scope} scope and posts them as settings`, async () => {
      const settings = vi.fn();
      await act(async () => {
        root.render(
          createElement(ChatToolsMemory, {
            t: state(scope) as never,
            focusedId: scope === 'group' ? 'm1' : null,
            reloadKey: 1,
            settings,
          }),
        );
        await Promise.resolve();
      });
      const text = container.textContent ?? '';
      expect(text).toContain('Use memory (RAG)');
      expect(text).toContain('Past moments per reply');
      const box = container.querySelector<HTMLInputElement>('.tool-body input[type="checkbox"]');
      expect(box).not.toBeNull();
      act(() => box!.click());
      expect(settings).toHaveBeenCalledWith({ ragEnabled: false });
    });
  }
});
