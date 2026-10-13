// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// On a Remote API the phone desk shows only what that host takes: host tiles,
// the key box for a host with no key, the model, its sizes, and Generate. The
// words and choices come from the computer's /api/image/remote-panel.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, button, click, container, createElement, gets, mount, readyFacts, reset, serve, settle,
  text, type, unmount,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { StudioDesk } = await import('./StudioDesk');

const choice = (value: string, label: string, selected = false) => ({ value, label, selected });

const nanoPanel = {
  hosts: [
    { id: 'nano', label: 'Nano-GPT', url: 'https://nano-gpt.com/api/v1', sub: 'Key saved', selected: true, hasKey: true },
    { id: 'openrouter', label: 'OpenRouter', url: 'https://openrouter.ai/api/v1', sub: 'Add a key', selected: false, hasKey: false },
    { id: 'xai', label: 'xAI', url: 'https://api.x.ai/v1', sub: 'SuperGrok sign-in', selected: false, hasKey: true },
  ],
  hostId: 'nano',
  hostLabel: 'Nano-GPT',
  url: 'https://nano-gpt.com/api/v1',
  billing: 'Bills your Nano-GPT account per image.',
  needsKey: false,
  keyPrompt: 'Paste your Nano-GPT key to use it here',
  keyHint: 'sk-…',
  keyNote: "Saved in the same key vault as chat. It does not change chat's provider.",
  needsKeyLine: 'Add a Nano-GPT key, or pick another host.',
  reachable: true,
  status: 'Reachable · 243 models',
  modelName: 'Z-Image Turbo',
  modelId: 'z-image-turbo',
  badges: ['Text to image', 'Pro included'],
  price: 'Included with your Nano-GPT Pro plan.',
  sizeMode: 'pixels',
  sizeTitle: 'Size',
  sizes: [choice('1024x1024', '1024×1024'), choice('1024x1536', '1024×1536', true)],
  resolutions: [choice('1k', '1k', true), choice('2k', '2k')],
  sizeNote: 'Sizes Z-Image Turbo accepts on Nano-GPT. Other models list their own.',
};

const keylessPanel = {
  ...nanoPanel,
  hosts: nanoPanel.hosts.map((h) => ({ ...h, selected: h.id === 'openrouter' })),
  hostId: 'openrouter',
  hostLabel: 'OpenRouter',
  url: 'https://openrouter.ai/api/v1',
  billing: 'Bills your OpenRouter account per image.',
  needsKey: true,
  keyPrompt: 'Paste your OpenRouter key to use it here',
  keyHint: 'sk-or-…',
  needsKeyLine: 'Add an OpenRouter key, or pick another host.',
};

const xaiPanel = {
  ...nanoPanel,
  hostId: 'xai',
  hostLabel: 'xAI',
  url: 'https://api.x.ai/v1',
  sizeMode: 'xai',
  sizeTitle: 'Aspect ratio',
  sizes: [choice('1:1', '1:1'), choice('2:3', '2:3', true), choice('auto', 'Auto')],
  sizeNote: 'Sends 2:3 at 1k. xAI takes a shape and a resolution, not exact pixels.',
};

const cfg = { ...baseConfig, backend: 'remote', model: 'z-image-turbo', imageRemoteHost: 'nano' };

afterEach(() => {
  unmount();
  reset();
});

const boot = async (panel: unknown, over: Record<string, unknown> = {}) => {
  serve({
    'GET /api/image/studio/ready': { ...readyFacts, primary: 'z-image-turbo' },
    'GET /api/image/remote-panel': panel,
    'GET /api/image/models': { models: [{ id: 'flux-2-pro', name: 'FLUX.2 Pro', label: 'FLUX.2 Pro · paid', isPaid: true }] },
  });
  const p = {
    cfg,
    onConfig: vi.fn(),
    save: vi.fn().mockResolvedValue(true),
    totpEnabled: false,
    prompt: 'a porch at dusk',
    onPrompt: vi.fn(),
    onGenerate: vi.fn(),
    ...over,
  };
  mount(createElement(StudioDesk, p));
  await settle();
  return p;
};

describe('the Remote API stove', () => {
  it('shows the host, model and sizes, and none of the local knobs', async () => {
    await boot(nanoPanel);

    for (const words of ['Remote API', 'Nano-GPT', 'OpenRouter', 'xAI', 'Bills your Nano-GPT account per image.',
      'Reachable · 243 models', 'Z-Image Turbo', 'z-image-turbo', 'Pro included', '1024×1536',
      'Sizes Z-Image Turbo accepts on Nano-GPT. Other models list their own.']) {
      expect(text()).toContain(words);
    }
    for (const gone of ['LoRA', 'Advanced', 'Change graph', 'CivitAI', 'Width']) {
      expect(text()).not.toContain(gone);
    }
    expect(gets('/api/image/remote-panel')[0].path).toContain('mode=create');
  });

  it('saves the host a tile picks', async () => {
    const p = await boot(nanoPanel);

    click(/^OpenRouter/);
    await settle();

    expect(p.save).toHaveBeenCalledWith({ imageRemoteHost: 'openrouter' });
  });

  it('saves the size a pill picks for the model on the desk', async () => {
    const p = await boot(nanoPanel);

    click('1024×1024');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ remoteSize: '1024x1024', mode: 'create' });
  });

  it('takes a ratio and a resolution on xAI', async () => {
    const p = await boot(xaiPanel);

    expect(text()).toContain('Aspect ratio');
    expect(text()).toContain('Resolution');
    click('Auto');
    click('2k');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ xaiAspect: 'auto' });
    expect(p.save).toHaveBeenCalledWith({ xaiResolution: '2k' });
  });

  it('asks for a key, with the web password, before a keyless host can generate', async () => {
    const p = await boot(keylessPanel);

    expect(text()).toContain('Paste your OpenRouter key to use it here');
    expect(text()).toContain('Add an OpenRouter key, or pick another host.');
    expect(text()).not.toContain('Change model');
    expect(button('Generate')!.disabled).toBe(true);
    type('#fp-remote-key', 'sk-or-123');
    expect(button('Save key')!.disabled).toBe(true);
    type('input[autocomplete="current-password"]', 'hunter2');
    click('Save key');
    await settle();

    expect(p.save).toHaveBeenCalledWith({ apiKey: 'sk-or-123', currentPassword: 'hunter2' });
  });

  it('picks a model from the host list', async () => {
    const p = await boot(nanoPanel);

    click('Change model');
    await settle();
    click(/FLUX\.2 Pro/);
    await settle();

    expect(p.save).toHaveBeenCalledWith({ model: 'flux-2-pro' });
  });

  it('generates when ready', async () => {
    const p = await boot(nanoPanel);

    expect(container.querySelector('.fp-remote-generate')).not.toBeNull();
    click('Generate');

    expect(p.onGenerate).toHaveBeenCalledWith({ mode: 'create', picture: null });
  });
});
