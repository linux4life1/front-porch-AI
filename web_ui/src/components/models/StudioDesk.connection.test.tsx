// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone can change the server the pictures come from: the local server's
// address (which needs the web password, as it decides where generation goes)
// and Draw Things' port (which does not), and which backend is used.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, blur, button, click, container, createElement, field, gets, mount, readyFacts, reset,
  serve, settle, text, type, unmount,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');

const props = (over: Record<string, unknown> = {}) => ({
  cfg: baseConfig,
  onConfig: vi.fn(),
  save: vi.fn().mockResolvedValue(true),
  totpEnabled: false,
  prompt: '',
  onPrompt: vi.fn(),
  onGenerate: vi.fn(),
  ...over,
});

afterEach(() => {
  unmount();
  reset();
});

const boot = async (over: Record<string, unknown> = {}) => {
  serve({ 'GET /api/image/studio/ready': readyFacts });
  const p = props(over);
  mount(createElement(StudioDesk, p));
  await settle();
  return p;
};

describe('the local server\'s address', () => {
  it('is shown, and asks for nothing while it is unchanged', async () => {
    await boot();

    expect(field<HTMLInputElement>('input[aria-label="Server address"]').value).toBe('http://127.0.0.1:8188');
    expect(container.querySelector('input[type="password"]')).toBeNull();
    expect(button('Save address')).toBeUndefined();
  });

  it('needs the web password to be saved, and sends it with the address', async () => {
    const p = await boot();

    type('input[aria-label="Server address"]', 'http://192.168.1.20:8188');
    expect(button('Save address')!.disabled).toBe(true);
    type('input[type="password"]', 'hunter2');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ comfyUrl: 'http://192.168.1.20:8188', currentPassword: 'hunter2' });
    // The password is not kept once it has been used.
    expect(field<HTMLInputElement>('input[type="password"]').value).toBe('');
    // What Ready says is asked again for the new address.
    expect(gets('/api/image/studio/ready').length).toBeGreaterThan(1);
  });

  it('sends the 2FA code too when the account has one', async () => {
    const p = await boot({ totpEnabled: true });

    type('input[aria-label="Server address"]', 'http://192.168.1.20:8188');
    type('input[type="password"]', 'hunter2');
    type('input[inputmode="numeric"]', '123456');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledWith({
      comfyUrl: 'http://192.168.1.20:8188',
      currentPassword: 'hunter2',
      totpCode: '123456',
    });
  });

  it('stays open, with the password kept, when the computer refuses', async () => {
    const p = await boot({ save: vi.fn().mockResolvedValue(false) });

    type('input[aria-label="Server address"]', 'http://192.168.1.20:8188');
    type('input[type="password"]', 'wrong');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledTimes(1);
    expect(field<HTMLInputElement>('input[type="password"]').value).toBe('wrong');
    expect(button('Save address')).toBeDefined();
  });

  it('is Automatic1111\'s own address on Automatic1111', async () => {
    const p = await boot({ cfg: { ...baseConfig, backend: 'a1111' } });

    expect(field<HTMLInputElement>('input[aria-label="Server address"]').value).toBe('http://127.0.0.1:7860');
    type('input[aria-label="Server address"]', 'http://10.0.0.5:7860');
    type('input[type="password"]', 'hunter2');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ localUrl: 'http://10.0.0.5:7860', currentPassword: 'hunter2' });
  });

  it('is not asked for on a remote backend', async () => {
    await boot({ cfg: { ...baseConfig, backend: 'remote' } });

    expect(container.querySelector('input[aria-label="Server address"]')).toBeNull();
    expect(text()).not.toContain('Not running');
  });
});

describe('Draw Things', () => {
  const cfg = { ...baseConfig, backend: 'drawthings', drawThingsHost: '10.0.0.9', drawThingsPort: 7859 };

  it('needs the password to save a new port, and saves nothing before', async () => {
    const p = await boot({ cfg });

    expect(field<HTMLInputElement>('input[aria-label="Draw Things port"]').value).toBe('7859');
    expect(container.querySelector('input[type="password"]')).toBeNull();
    type('input[aria-label="Draw Things port"]', '7900');
    blur('input[aria-label="Draw Things port"]');
    await settle();

    expect(p.save).not.toHaveBeenCalled();
    expect(container.querySelector('input[type="password"]')).not.toBeNull();
    expect(button('Save port')!.disabled).toBe(true);

    type('input[type="password"]', 'hunter2');
    click('Save port');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ drawThingsPort: 7900, currentPassword: 'hunter2' });
  });

  it('saves a new host and port together, with the password once', async () => {
    const p = await boot({ cfg });

    type('input[aria-label="Draw Things host"]', '10.0.0.10');
    type('input[aria-label="Draw Things port"]', '7900');
    type('input[type="password"]', 'hunter2');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledWith({
      drawThingsHost: '10.0.0.10',
      drawThingsPort: 7900,
      currentPassword: 'hunter2',
    });
  });

  it('does not offer to save a port that is not one', async () => {
    const p = await boot({ cfg });

    for (const bad of ['0', '70000', '']) {
      type('input[aria-label="Draw Things port"]', bad);
      blur('input[aria-label="Draw Things port"]');
      await settle();
      expect(container.querySelector('input[type="password"]')).toBeNull();
    }

    expect(p.save).not.toHaveBeenCalled();
  });

  it('needs the password for a new host', async () => {
    const p = await boot({ cfg });

    type('input[aria-label="Draw Things host"]', '10.0.0.10');
    expect(container.querySelector('input[type="password"]')).not.toBeNull();
    type('input[type="password"]', 'hunter2');
    click('Save address');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ drawThingsHost: '10.0.0.10', currentPassword: 'hunter2' });
  });
});

describe('the backend', () => {
  it('is changed by naming it', async () => {
    const p = await boot();

    click('Draw Things');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ backend: 'drawthings' });
  });

  it('shows the one in use as pressed', async () => {
    await boot();
    expect(button('ComfyUI')!.getAttribute('aria-pressed')).toBe('true');
    expect(button('Remote')!.getAttribute('aria-pressed')).toBe('false');
  });

  it('can be checked again without changing anything', async () => {
    const p = await boot();
    const before = gets('/api/image/studio/ready').length;

    click('Check');
    await settle();

    expect(gets('/api/image/studio/ready').length).toBe(before + 1);
    expect(p.save).not.toHaveBeenCalled();
  });

  it('says when nothing answers', async () => {
    serve({ 'GET /api/image/studio/ready': { ...readyFacts, reachable: false } });
    mount(createElement(StudioDesk, props()));
    await settle();

    expect(text()).toContain('Not running');
  });
});
