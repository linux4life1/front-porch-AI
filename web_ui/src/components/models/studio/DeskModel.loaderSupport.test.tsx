// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, expect, it, vi } from 'vitest';
import { DeskModel } from './DeskModel';
import { baseConfig, button, click, createElement, mount, unmount } from './deskTestKit';

afterEach(unmount);

it('offers confirmation even when the loader cannot be updated locally', () => {
  const onLoaderSupport = vi.fn();
  mount(createElement(DeskModel, {
    cfg: baseConfig, mode: 'edit', facts: { kind: 'needsLoaderUpdate', canUpdateLoader: false },
    onGraph: vi.fn(), onModel: vi.fn(), onCivitai: vi.fn(), onLoaderSupport,
  }));
  click('Use existing GGUF support…');
  expect(onLoaderSupport).toHaveBeenCalledOnce();
});

it('offers revocation after confirmation and disables it during generation', () => {
  const onLoaderSupport = vi.fn();
  mount(createElement(DeskModel, {
    cfg: baseConfig, mode: 'create', facts: { kind: 'ready', loaderSupportConfirmed: true },
    onGraph: vi.fn(), onModel: vi.fn(), onCivitai: vi.fn(), onLoaderSupport, busy: true,
  }));
  expect(button('Recheck GGUF support')?.disabled).toBe(true);
  click('Recheck GGUF support');
  expect(onLoaderSupport).not.toHaveBeenCalled();
});

it('does not show the control for other backends', () => {
  mount(createElement(DeskModel, {
    cfg: { ...baseConfig, backend: 'remote' }, mode: 'edit',
    facts: { kind: 'needsLoaderUpdate', loaderSupportConfirmed: true },
    onGraph: vi.fn(), onModel: vi.fn(), onCivitai: vi.fn(), onLoaderSupport: vi.fn(),
  }));
  expect(button('Use existing GGUF support…')).toBeUndefined();
  expect(button('Recheck GGUF support')).toBeUndefined();
});
