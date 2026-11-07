// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The "add to scene" picker (/join) must list every library character no
// matter which folder holds them. /api/characters defaults to scope
// =currentFolder, which with no folder id means "unfoldered top level only" —
// exactly the home page's unsorted grid. The picker must ask for
// scope=allCharacters or subfolder characters are unpickable even though
// /join <name> would resolve them. Desktop twin: SceneGuestPickerDialog reads
// the full joinable pool (lib/services/chat/doors/cast/guest_join.dart).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const requestedUrls: string[] = [];

vi.mock('../api/client', () => ({
  api: {
    avatarUrl: (path: string) => path,
    get: (url: string) => {
      requestedUrls.push(url);
      return Promise.resolve([]);
    },
  },
}));

const { CharacterPicker } = await import('./CharacterPicker');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  requestedUrls.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('CharacterPicker library scope', () => {
  it('asks for every folder when browsing the join pool', async () => {
    act(() => {
      root.render(createElement(CharacterPicker, { onPick: () => {}, onClose: () => {} }));
    });
    await act(async () => {
      await Promise.resolve();
    });
    expect(requestedUrls).toHaveLength(1);
    expect(requestedUrls[0]).toMatch(/scope=allCharacters/);
  });
});
