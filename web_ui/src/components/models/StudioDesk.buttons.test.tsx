// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every button on the phone desk does something: Write it for me writes a
// prompt for the subject picked, the subject buttons say who it is about,
// Expression pack opens the pack panel, and Choose file takes a graph after the
// password.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  baseConfig, blur, button, calls, choose, click, container, createElement, field, gets, mount,
  posts, readyFacts, refuse, reset, serve, settle, sheetText, text, type, unmount,
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

const boot = async (over: Record<string, unknown> = {}, routes: Record<string, unknown> = {}) => {
  serve({
    'GET /api/image/studio/ready': readyFacts,
    'GET /api/image/comfy-catalog': { graphs: [], editGraphs: [] },
    'GET /api/image/expression-pack': refuse(404, 'No expression pack'),
    ...routes,
  });
  const p = props(over);
  mount(createElement(StudioDesk, p));
  await settle();
  return p;
};

describe('Write it for me', () => {
  it('asks the computer to write for the subject, working from what was typed', async () => {
    const p = await boot(
      { prompt: 'wearing a red scarf' },
      { 'POST /api/image/studio/write-prompt': { prompt: 'a woman in a red scarf on a porch' } },
    );

    click('Character');
    click('Write it for me');
    await settle();

    expect(posts('/api/image/studio/write-prompt').map((c) => c.body)).toEqual([
      { subject: 'char', instruction: 'wearing a red scarf' },
    ]);
    expect(p.onPrompt).toHaveBeenCalledWith('a woman in a red scarf on a porch');
  });

  it('is freeform until another subject is picked, and follows the last pick', async () => {
    await boot({}, { 'POST /api/image/studio/write-prompt': { prompt: 'x' } });

    expect(button('Freeform')!.getAttribute('aria-pressed')).toBe('true');
    click('Write it for me');
    await settle();
    click('Your persona');
    expect(button('Freeform')!.getAttribute('aria-pressed')).toBe('false');
    expect(button('Your persona')!.getAttribute('aria-pressed')).toBe('true');
    click('Write it for me');
    await settle();

    expect(posts('/api/image/studio/write-prompt').map((c) => (c.body as { subject: string }).subject)).toEqual([
      'free',
      'persona',
    ]);
  });

  it('is busy while it writes, and says why when it cannot', async () => {
    let finish: (v: unknown) => void = () => {};
    const p = await boot(
      {},
      { 'POST /api/image/studio/write-prompt': () => new Promise((resolve) => (finish = resolve)) },
    );

    click('Write it for me');
    await settle();
    expect(button('Writing…')!.disabled).toBe(true);
    finish(refuse(409, 'Open a chat first, then try again.'));
    await settle();

    expect(text()).toContain('Open a chat first, then try again.');
    expect(p.onPrompt).not.toHaveBeenCalled();
    expect(button('Write it for me')!.disabled).toBe(false);
  });
});

describe('Choose picture', () => {
  it('opens the picture chooser', async () => {
    await boot();
    const input = field('input[aria-label="Picture file"]');
    const opened = vi.spyOn(input, 'click');

    click('Choose picture');

    expect(opened).toHaveBeenCalled();
  });
});

describe('Expression pack', () => {
  it('opens the pack panel, where a pack can be started', async () => {
    await boot({}, { 'GET /api/characters': [{ id: 'c1', name: 'Mara' }] });
    expect(button('Start pack')).toBeUndefined();

    click('Expression pack');
    await settle();

    expect(button('Start pack')).toBeDefined();
    expect(button('Expression pack')!.getAttribute('aria-expanded')).toBe('true');
    expect(text()).toContain('runs your Edit graph');
  });
});

describe('Choose file', () => {
  const graph = new TextEncoder().encode('{"1": {"class_type": "KSampler", "inputs": {}}}');
  const file = () => new File([graph], 'porch.json', { type: 'application/json' });
  const open = async (routes: Record<string, unknown> = {}, over: Record<string, unknown> = {}) => {
    const p = await boot(over, routes);
    click('Change graph');
    await settle();
    return p;
  };

  it('opens the file chooser', async () => {
    await open();
    const input = field('input[aria-label="Workflow file"]');
    const opened = vi.spyOn(input, 'click');

    click('Choose file');

    expect(opened).toHaveBeenCalled();
  });

  it('holds the file until the password is given, then sends it whole', async () => {
    const stored = { stored: true, stance: 'create', mode: 'create', title: 'porch.json', nodes: 1, config: baseConfig };
    const p = await open({ 'POST /api/image/studio/graph': stored });

    choose('input[aria-label="Workflow file"]', file());
    await settle();
    expect(sheetText()).toContain('porch.json needs your web password to be used.');
    expect(posts('/api/image/studio/graph')).toHaveLength(0);
    expect(button('Use this graph')!.disabled).toBe(true);

    type('input[type="password"]', 'hunter2');
    click('Use this graph');
    await settle();

    const body = posts('/api/image/studio/graph')[0].body as Record<string, unknown>;
    expect(body).toMatchObject({ name: 'porch.json', mode: 'create', currentPassword: 'hunter2' });
    expect(atob(body.data as string)).toBe('{"1": {"class_type": "KSampler", "inputs": {}}}');
    expect(body).not.toHaveProperty('useFor');
    expect(p.onConfig).toHaveBeenCalledWith(baseConfig);
    expect(container.querySelector('[role="dialog"]')).toBeNull();
    expect(text()).toContain('porch.json is the workflow for this portrait.');
  });

  it('asks which mode when the graph is for the other one, then sends the answer', async () => {
    let n = 0;
    await open({
      'POST /api/image/studio/graph': () =>
        n++ === 0
          ? { stored: false, stance: 'edit', nodes: 1 }
          : { stored: true, stance: 'edit', mode: 'edit', title: 'porch.json', config: baseConfig },
    });

    choose('input[aria-label="Workflow file"]', file());
    await settle();
    type('input[type="password"]', 'hunter2');
    click('Use this graph');
    await settle();
    expect(sheetText()).toContain('This graph is for Edit.');

    click('Use it for Edit');
    await settle();

    expect(posts('/api/image/studio/graph').map((c) => (c.body as { useFor?: string }).useFor)).toEqual([undefined, 'edit']);
    expect(text()).toContain('porch.json is the workflow for this edit.');
  });

  it('asks Create or Edit when the graph does not say', async () => {
    let n = 0;
    await open({
      'POST /api/image/studio/graph': () =>
        n++ === 0 ? { stored: false, stance: 'unstated' } : { stored: true, stance: 'unstated', mode: 'create', config: baseConfig },
    });

    choose('input[aria-label="Workflow file"]', file());
    await settle();
    type('input[type="password"]', 'hunter2');
    click('Use this graph');
    await settle();
    expect(sheetText()).toContain('This graph doesn’t say Create or Edit.');

    click('Use for Create');
    await settle();

    expect((posts('/api/image/studio/graph')[1].body as { useFor: string }).useFor).toBe('create');
  });

  it('sends the 2FA code when there is one to send', async () => {
    await open({ 'POST /api/image/studio/graph': { stored: true, stance: 'create', config: baseConfig } }, { totpEnabled: true });

    choose('input[aria-label="Workflow file"]', file());
    await settle();
    type('input[type="password"]', 'hunter2');
    type('input[inputmode="numeric"]', '123456');
    click('Use this graph');
    await settle();

    expect(posts('/api/image/studio/graph')[0].body).toMatchObject({ currentPassword: 'hunter2', totpCode: '123456' });
  });

  it('shows the computer\'s words when the file is not a graph or the password is wrong', async () => {
    let answer: unknown = refuse(400, 'That file isn’t a ComfyUI graph.');
    await open({ 'POST /api/image/studio/graph': () => answer });

    choose('input[aria-label="Workflow file"]', file());
    await settle();
    type('input[type="password"]', 'hunter2');
    click('Use this graph');
    await settle();
    expect(sheetText()).toContain('That file isn’t a ComfyUI graph.');

    answer = refuse(401, 'Current password is incorrect');
    click('Use this graph');
    await settle();
    expect(sheetText()).toContain('Current password is incorrect');
  });

  it('refuses a file that is too large before sending it', async () => {
    await open();

    choose(
      'input[aria-label="Workflow file"]',
      new File([new Uint8Array(8 * 1024 * 1024 + 1)], 'big.json'),
    );
    await settle();

    expect(sheetText()).toContain('That file is too large to use.');
    expect(posts('/api/image/studio/graph')).toHaveLength(0);
    expect(button('Use this graph')).toBeUndefined();
  });
});
