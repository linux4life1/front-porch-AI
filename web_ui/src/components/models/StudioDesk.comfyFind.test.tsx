// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When the address the person gave does not answer but ComfyUI does
// somewhere else on the computer, the phone says where, and "Use this" puts
// that address in the field (saving it still needs the web password).

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, button, click, container, createElement, field, mount, posts, readyFacts, reset, serve, settle,
  text, type, unmount,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');

afterEach(() => {
  unmount();
  reset();
});

const boot = async (facts: Record<string, unknown>) => {
  serve({ 'GET /api/image/studio/ready': { ...readyFacts, ...facts } });
  const save = vi.fn().mockResolvedValue(true);
  mount(
    createElement(StudioDesk, {
      cfg: { ...baseConfig, backend: 'comfyui', comfyUrl: 'http://127.0.0.1:8189' },
      onConfig: vi.fn(),
      save,
      totpEnabled: false,
      prompt: '',
      onPrompt: vi.fn(),
      onGenerate: vi.fn(),
    }),
  );
  await settle();
  return save;
};

describe('a ComfyUI found elsewhere', () => {
  it('is named, and Use this puts it in the address, saved with the password', async () => {
    const save = await boot({ reachable: false, neighborUrl: 'http://127.0.0.1:8188' });
    expect(text()).toContain('ComfyUI answers at http://127.0.0.1:8188');

    click('Use this');
    await settle();
    expect(field<HTMLInputElement>('input[aria-label="Server address"]').value).toBe('http://127.0.0.1:8188');
    expect(save).not.toHaveBeenCalled();

    type('input[type="password"]', 'hunter2');
    click('Save address');
    await settle();
    expect(save).toHaveBeenCalledWith({ comfyUrl: 'http://127.0.0.1:8188', currentPassword: 'hunter2' });
    expect(posts('/api/image/config')).toHaveLength(0);
  });

  it('is not shown when there is none', async () => {
    await boot({ reachable: true, neighborUrl: '' });
    expect(text()).not.toContain('ComfyUI answers at');
    expect(button('Use this')).toBeUndefined();
    expect(container.querySelector('input[type="password"]')).toBeNull();
  });
});
