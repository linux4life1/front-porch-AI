// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Image generation card on the phone: what Generate sends for Create and
// for Edit, how far the picture is while it is made, the picture and putting
// it into the chat, and how a change is saved.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, button, calls, choose, click, container, createElement, field, gets, mount, png, posts,
  readyFacts, refuse, reset, serve, settle, text, type, unmount, until,
} from './studio/deskTestKit';

vi.mock('../../api/client', async () => (await import('./studio/deskTestKit')).clientMock);

const { ImageGen } = await import('./ImageGen');

afterEach(() => {
  unmount();
  reset();
});

const routes = (over: Record<string, unknown> = {}) => ({
  'GET /api/image/config': baseConfig,
  'GET /api/auth/state': { totpEnabled: false },
  'GET /api/image/studio/ready': readyFacts,
  'GET /api/image/expression-pack': refuse(404, 'No expression pack'),
  'POST /api/image/generate': { image: 'data:image/png;base64,AAAA', filename: 'made_1.png' },
  ...over,
});

const open = async (over: Record<string, unknown> = {}, onError = vi.fn()) => {
  serve(routes(over));
  mount(createElement(ImageGen, { onError, progressMs: 5 }));
  await settle(8);
  return onError;
};

describe('Generate', () => {
  it('sends the prompt for a Create, and shows the picture with a way to put it in the chat', async () => {
    await open();
    type('textarea[aria-label="Prompt"]', 'a quiet porch');

    click('Generate');
    await settle();

    expect(posts('/api/image/generate').map((c) => c.body)).toEqual([{ prompt: 'a quiet porch', mode: 'create' }]);
    expect((container.querySelector('img[alt="Generated"]') as HTMLImageElement).src).toContain('data:image/png');
    expect(text()).toContain('Insert into chat');
  });

  it('sends an Edit with the picture it was given', async () => {
    await open();
    type('textarea[aria-label="Prompt"]', 'make it night');
    click('Edit');
    await settle();
    choose('input[aria-label="Picture file"]', png());
    await settle(10);

    click('Generate');
    await settle();

    const body = posts('/api/image/generate')[0].body as Record<string, unknown>;
    expect(body.mode).toBe('edit');
    expect(body.prompt).toBe('make it night');
    expect(body.referenceImage).toMatch(/^data:image\/png;base64,/);
    expect(body).not.toHaveProperty('referenceFilename');
  });

  it('can edit the picture it just made, by its saved name', async () => {
    await open();
    type('textarea[aria-label="Prompt"]', 'a quiet porch');
    click('Generate');
    await settle();

    click('Edit');
    await settle();
    click('Use the last picture I made');
    await settle();
    type('textarea[aria-label="Prompt"]', 'add a lantern');
    click('Generate');
    await settle();

    const second = posts('/api/image/generate')[1].body as Record<string, unknown>;
    expect(second).toMatchObject({ mode: 'edit', referenceFilename: 'made_1.png' });
    expect(second).not.toHaveProperty('referenceImage');
  });

  it('puts the picture into the chat with the prompt that made it', async () => {
    await open({ 'POST /api/chat/insert-image': { ok: true } });
    type('textarea[aria-label="Prompt"]', 'a quiet porch');
    click('Generate');
    await settle();

    click('Insert into chat');
    await settle();

    expect(posts('/api/chat/insert-image').map((c) => c.body)).toEqual([
      { filename: 'made_1.png', prompt: 'a quiet porch' },
    ]);
    expect(button('Inserted ✓')!.disabled).toBe(true);
  });

  it('shows why it failed, and tells the page', async () => {
    const onError = await open({ 'POST /api/image/generate': refuse(400, 'Pick a picture to edit.') });
    type('textarea[aria-label="Prompt"]', 'a quiet porch');

    click('Generate');
    await settle();

    expect(text()).toContain('Pick a picture to edit.');
    expect(onError).toHaveBeenCalledWith('Pick a picture to edit.');
    expect(container.querySelector('img[alt="Generated"]')).toBeNull();
    expect(button('Generate')!.disabled).toBe(false);
  });
});

describe('while a picture is made', () => {
  it('asks how far it is, shows it, and stops asking when it is done', async () => {
    let finish: (v: unknown) => void = () => {};
    let percent = 0.25;
    await open({
      'POST /api/image/generate': () => new Promise((resolve) => (finish = resolve)),
      'GET /api/image/config': () => ({ ...baseConfig, isGenerating: true, genProgress: percent }),
    });
    type('textarea[aria-label="Prompt"]', 'a quiet porch');

    click('Generate');
    await until(() => text().includes('Painting… 25%'));
    percent = 0.5;
    await until(() => text().includes('Painting… 50%'));
    expect(button('Generate')!.disabled).toBe(true);

    finish({ image: 'data:image/png;base64,AAAA', filename: 'made_1.png' });
    await settle();
    const asked = gets('/api/image/config').length;
    await new Promise((r) => setTimeout(r, 40));

    expect(gets('/api/image/config').length).toBe(asked);
    expect(text()).not.toContain('Painting…');
  });

  it('shows a bar that does not know the percent when the computer does not', async () => {
    let finish: (v: unknown) => void = () => {};
    await open({
      'POST /api/image/generate': () => new Promise((resolve) => (finish = resolve)),
      'GET /api/image/config': () => ({ ...baseConfig, genProgress: null }),
    });
    type('textarea[aria-label="Prompt"]', 'a quiet porch');
    click('Generate');
    await settle(4);

    const bar = container.querySelector('progress[aria-label="Generation progress"]') as HTMLProgressElement;
    expect(bar).not.toBeNull();
    expect(bar.hasAttribute('value')).toBe(false);
    expect(text()).not.toContain('Painting…');
    finish({ image: 'data:image/png;base64,AAAA', filename: null });
  });
});

describe('saving a change', () => {
  it('shows it at once and takes the computer\'s answer', async () => {
    await open({ 'POST /api/image/config': { ...baseConfig, size: '512x512' } });

    click('512×512');
    await settle();

    expect(posts('/api/image/config').map((c) => c.body)).toEqual([{ size: '512x512' }]);
    expect(pressedSize()).toBe('512×512');
  });

  it('puts things back and says why when the computer refuses', async () => {
    const onError = await open({ 'POST /api/image/config': refuse(400, 'Nope.') });
    const before = gets('/api/image/config').length;

    click('512×512');
    await settle();

    expect(onError).toHaveBeenCalledWith('Nope.');
    expect(gets('/api/image/config').length).toBe(before + 1);
    expect(pressedSize()).toBe('1024×1024');
  });

  it('asks for the 2FA code once the computer says it is needed', async () => {
    await open({
      'POST /api/image/config': refuse(401, 'A 2FA code is required', { totpRequired: true }),
    });
    type('input[aria-label="Server address"]', 'http://10.0.0.5:8188');
    type('input[type="password"]', 'hunter2');
    expect(container.querySelector('input[inputmode="numeric"]')).toBeNull();

    click('Save address');
    await settle();

    expect(container.querySelector('input[inputmode="numeric"]')).not.toBeNull();
  });
});

describe('around the desk', () => {
  it('starts a computer that names no graph on the built-in ones', async () => {
    const { comfyCreateWorkflowId, comfyEditWorkflowId, ...bare } = baseConfig;
    void comfyCreateWorkflowId;
    void comfyEditWorkflowId;
    await open({
      'GET /api/image/config': bare,
      'GET /api/image/studio/ready': { ...readyFacts, workflowId: undefined },
    });

    expect(text()).toContain('Workflow · Text to image · sd');
    click('Edit');
    await settle();
    expect(text()).toContain('Workflow · Edit · qwen_image_edit');
  });

  it('shows the pack a computer is running, above the desk', async () => {
    await open({
      'GET /api/image/expression-pack': { running: true, filenames: ['joy.png'], verdicts: [] },
    });

    expect(text().indexOf('Expression pack running')).toBeLessThan(text().indexOf('Subject'));
    expect(text()).toContain('joy.png');
  });

  it('offers the remote host and model on a remote backend, and saves the host', async () => {
    await open({
      'GET /api/image/config': {
        ...baseConfig,
        backend: 'remote',
        imageRemoteHost: 'nano',
        imageRemoteHosts: [
          { id: 'nano', label: 'Nano-GPT', url: 'https://nano-gpt.com/api/v1', hasKey: true },
          { id: 'openrouter', label: 'OpenRouter', url: 'https://openrouter.ai/api/v1', hasKey: true },
        ],
      },
      'GET /api/image/models': { models: [] },
      'POST /api/image/config': baseConfig,
    });

    expect(text()).toContain('OpenRouter');
    click('OpenRouter');
    await settle();

    expect(posts('/api/image/config').map((c) => c.body)).toEqual([{ imageRemoteHost: 'openrouter' }]);
  });

  it('shows nothing until the config has been read', async () => {
    serve(routes({ 'GET /api/image/config': () => new Promise(() => {}) }));
    mount(createElement(ImageGen, { onError: vi.fn() }));
    await settle();

    expect(container.textContent).toBe('');
  });

  it('asks for nothing that changes anything on its own', async () => {
    await open();
    await settle(10);

    expect(calls.filter((c) => c.method === 'POST')).toEqual([]);
    expect(field('textarea[aria-label="Prompt"]')).not.toBeNull();
  });
});

/** The size button that is pressed. */
function pressedSize() {
  return [...container.querySelectorAll('button[aria-pressed="true"].fp-pill')]
    .map((b) => b.textContent ?? '')
    .find((label) => /×/.test(label));
}
