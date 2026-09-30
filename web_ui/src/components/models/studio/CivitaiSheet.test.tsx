// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Get a model or a LoRA from CivitAI on the phone: search and the key go
// through the computer, the download runs there and the phone watches its
// percent and can stop it, adult results are asked for only when the app allows
// them, and saving the key needs the web password.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  button, calls, click, container, createElement, field, mount, pickOption, posts, refuse, reset, serve, settle, text,
  type, unmount, until,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { CivitaiSheet } = await import('./CivitaiSheet');

const row = (over: Record<string, unknown> = {}) => ({
  filename: 'portrait.safetensors',
  versionId: 42,
  type: 'Checkpoint',
  adult: false,
  name: 'Portrait Maker',
  downloads: 1234,
  previewUrl: 'https://image.civitai.com/x/hero.jpeg',
  ...over,
});

const props = (over: Record<string, unknown> = {}) => ({
  lora: false,
  backend: 'comfyui',
  adultAllowed: false,
  totpEnabled: false,
  onInstalled: vi.fn().mockResolvedValue('Saved to your models folder on this computer.'),
  onClose: vi.fn(),
  pollMs: 5,
  ...over,
});

const job = (over: Record<string, unknown> = {}) => ({
  jobId: 'j1', name: 'portrait.safetensors', state: 'running', received: 0, total: 100, percent: 0, ...over,
});

afterEach(() => {
  unmount();
  reset();
});

const open = async (over: Record<string, unknown> = {}, routes: Record<string, unknown> = {}) => {
  serve({
    'GET /api/image/civitai/credential': { saved: true },
    'GET /api/image/civitai/installed': { bases: [], models: [], loras: [] },
    'GET /api/image/civitai/search': { items: [row()], needsCredential: false },
    ...routes,
  });
  const p = props(over);
  mount(createElement(CivitaiSheet, p));
  await settle();
  return p;
};

const search = async (q = 'portrait') => {
  type('input[aria-label="Search"]', q);
  click('Search');
  await settle();
};

describe('searching', () => {
  it('sends the query, the kind and the base, and shows each result with its picture', async () => {
    await open({ lora: true });
    pickOption('select[aria-label="Base model"]', 'Qwen');
    await search('clothes');

    const sent = calls.find((c) => c.path.startsWith('/api/image/civitai/search'))!.path;
    const query = new URLSearchParams(sent.split('?')[1]);
    expect(query.get('q')).toBe('clothes');
    expect(query.get('sheet')).toBe('lora');
    expect(query.get('adult')).toBe('false');
    expect(text()).toContain('Portrait Maker');
    expect(text()).toContain('1,234 downloads');
    expect((container.querySelector('img') as HTMLImageElement).src).toBe('https://image.civitai.com/x/hero.jpeg');
  });

  it('says so when nothing matches, and when the search fails', async () => {
    await open({}, { 'GET /api/image/civitai/search': { items: [], needsCredential: false } });
    await search();
    expect(text()).toContain('CivitAI returned no models for that search.');

    serve({ 'GET /api/image/civitai/search': refuse(502, 'CivitAI search failed') });
    click('Search');
    await settle();
    expect(text()).toContain('CivitAI search failed');
  });

  it('asks for a key when adult results need one', async () => {
    await open({}, { 'GET /api/image/civitai/search': { items: [], needsCredential: true } });
    await search();
    expect(text()).toContain('Paste an API key to search adult models.');
  });

  it('hides a raw error page', async () => {
    await open({}, { 'GET /api/image/civitai/search': refuse(502, '<html>bad gateway</html>') });
    await search();
    expect(text()).toContain('CivitAI search failed.');
    expect(text()).not.toContain('<html>');
  });
});

describe('adult results', () => {
  it('cannot be asked for unless the app allows them', async () => {
    await open({ adultAllowed: false });
    expect(text()).not.toContain('Include adult models from civitai.red');

    unmount();
    await open({ adultAllowed: true });
    expect(text()).toContain('Include adult models from civitai.red');
  });

  it('are sent as asked, and leave the screen when turned off', async () => {
    await open(
      { adultAllowed: true },
      {
        'GET /api/image/civitai/search': {
          items: [row(), row({ filename: 'adult.safetensors', versionId: 43, name: 'Adult One', adult: true })],
          needsCredential: false,
        },
      },
    );
    field('input[type="checkbox"]').click();
    await settle();
    await search();
    expect(calls.at(-1)!.path).toContain('adult=true');
    expect(text()).toContain('Adult One');

    field('input[type="checkbox"]').click();
    await settle();

    expect(text()).not.toContain('Adult One');
    expect(text()).not.toContain('Portrait Maker');
  });

  it('never leave a row on screen that is adult while adult is off', async () => {
    await open(
      { adultAllowed: false },
      {
        'GET /api/image/civitai/search': {
          items: [row({ adult: true, name: 'Adult One' }), row({ filename: 'ok.safetensors', versionId: 9, name: 'Fine One' })],
          needsCredential: false,
        },
      },
    );
    await search();

    expect(text()).toContain('Fine One');
    expect(text()).not.toContain('Adult One');
  });
});

describe('a download', () => {
  const routes = (statuses: unknown[]) => {
    let n = 0;
    return {
      'POST /api/image/civitai/download': job(),
      'GET /api/image/civitai/download/status': () => statuses[Math.min(n++, statuses.length - 1)],
      'POST /api/image/civitai/download/cancel': { cancelled: true },
    };
  };

  it('is asked of the computer with only what it needs, and never with a key', async () => {
    await open({}, routes([job({ state: 'done', percent: 100 })]));
    await search();

    click('portrait.safetensors');
    await settle();

    expect(posts('/api/image/civitai/download').map((c) => c.body)).toEqual([
      { versionId: 42, backend: 'comfyui', adult: false, filename: 'portrait.safetensors', lora: false },
    ]);
  });

  it('shows how far it is, then picks the file into the desk', async () => {
    const p = await open(
      {},
      routes([
        job({ percent: 30 }),
        job({ percent: 30 }),
        job({ percent: 80 }),
        job({ state: 'done', percent: 100 }),
      ]),
    );
    await search();

    click('portrait.safetensors');
    await until(() => (container.querySelector('progress[aria-label="Download progress"]') as HTMLProgressElement | null)?.value === 30);
    expect(text()).toContain('Downloading on your computer…');
    expect(text()).toContain('30%');

    await new Promise((r) => setTimeout(r, 60));
    await settle();

    expect(container.querySelector('progress')).toBeNull();
    expect(p.onInstalled).toHaveBeenCalledWith('portrait.safetensors', false);
    expect(text()).toContain('Saved to your models folder on this computer.');
  });

  it('stops saying it is downloading once it is done, while the file is being picked', async () => {
    const p = await open(
      { onInstalled: vi.fn(() => new Promise<string>(() => {})) },
      routes([job({ percent: 50 }), job({ state: 'done', percent: 100 })]),
    );
    await search();

    click('portrait.safetensors');
    await until(() => (container.querySelector('progress[aria-label="Download progress"]') as HTMLProgressElement | null)?.value === 50);
    expect(text()).toContain('Downloading on your computer…');

    await new Promise((r) => setTimeout(r, 60));
    await settle();

    expect(p.onInstalled).toHaveBeenCalled();
    expect(text()).not.toContain('Downloading on your computer…');
  });

  it('can be cancelled from the phone', async () => {
    await open({}, routes([job({ percent: 10 })]));
    await search();
    click('portrait.safetensors');
    await until(() => !!button('Cancel download'));

    click('Cancel download');
    await settle();

    expect(posts('/api/image/civitai/download/cancel').map((c) => c.body)).toEqual([{ job: 'j1' }]);
  });

  it('is cancelled by closing the sheet', async () => {
    const p = await open({}, routes([job({ percent: 10 })]));
    await search();
    click('portrait.safetensors');
    await until(() => !!button('Cancel download'));

    click('Close');
    await settle();

    expect(posts('/api/image/civitai/download/cancel').map((c) => c.body)).toEqual([{ job: 'j1' }]);
    expect(p.onClose).toHaveBeenCalled();
  });

  it('is not started twice while it runs', async () => {
    await open({}, routes([job({ percent: 10 })]));
    await search();
    click('portrait.safetensors');
    await until(() => !!button('Cancel download'));

    click('portrait.safetensors');
    await settle();

    expect(posts('/api/image/civitai/download')).toHaveLength(1);
  });

  it('says what the computer said when it fails', async () => {
    const p = await open(
      {},
      routes([job({ state: 'failed', code: 'disk_full', error: 'There is not enough room on the disk.' })]),
    );
    await search();
    click('portrait.safetensors');
    await settle(5);

    expect(text()).toContain('There is not enough room on the disk.');
    expect(p.onInstalled).not.toHaveBeenCalled();
    expect(container.querySelector('progress')).toBeNull();
  });

  it('hides a raw page when that is what the computer had to say', async () => {
    await open({}, routes([job({ state: 'failed', code: 'network', error: '<html>bad gateway</html>' })]));
    await search();
    click('portrait.safetensors');
    await settle(5);

    expect(text()).toContain('CivitAI download failed.');
    expect(text()).not.toContain('<html>');
  });

  it('says so when it was cancelled on the computer', async () => {
    await open({}, routes([job({ state: 'cancelled' })]));
    await search();
    click('portrait.safetensors');
    await settle(5);

    expect(text()).toContain('The download was cancelled.');
  });

  it('shows the computer\'s refusal, and hides a raw page', async () => {
    await open({}, { 'POST /api/image/civitai/download': refuse(409, 'That file is already downloading.') });
    await search();
    click('portrait.safetensors');
    await settle();
    expect(text()).toContain('That file is already downloading.');

    serve({ 'POST /api/image/civitai/download': refuse(502, '<html>x</html>') });
    click('portrait.safetensors');
    await settle();
    expect(text()).toContain('CivitAI download failed.');
    expect(text()).not.toContain('<html>');
  });

  it('is not needed for a file that is already installed', async () => {
    const p = await open({}, {
      'GET /api/image/civitai/installed': { bases: [], models: ['Portrait.safetensors'], loras: [] },
    });
    await search();

    click('Installed');
    await settle();

    expect(posts('/api/image/civitai/download')).toHaveLength(0);
    expect(p.onInstalled).toHaveBeenCalledWith('portrait.safetensors', false);
  });

  it('is a LoRA when the sheet is the LoRA one', async () => {
    const p = await open({ lora: true }, routes([job({ state: 'done', percent: 100 })]));
    await search();
    click('portrait.safetensors');
    await settle(5);

    expect((posts('/api/image/civitai/download')[0].body as { lora: boolean }).lora).toBe(true);
    expect(p.onInstalled).toHaveBeenCalledWith('portrait.safetensors', true);
  });
});

describe('the key', () => {
  it('is only saved after the web password, and never shown again', async () => {
    await open({}, {
      'GET /api/image/civitai/credential': { saved: false },
      'POST /api/image/civitai/credential': { saved: true },
    });
    expect(container.querySelector('input[type="password"]')).not.toBeNull();

    type('input[autocomplete="off"]', 'sk-secret');
    expect(button('Save key')!.disabled).toBe(true);
    type('input[autocomplete="current-password"]', 'hunter2');
    click('Save key');
    await settle();

    expect(posts('/api/image/civitai/credential').map((c) => c.body)).toEqual([
      { token: 'sk-secret', currentPassword: 'hunter2' },
    ]);
    expect(text()).toContain('API key saved.');
    expect(container.querySelector('input[autocomplete="off"]')).toBeNull();
    expect(container.innerHTML).not.toContain('sk-secret');
  });

  it('is not called saved when the computer did not save it', async () => {
    await open({}, {
      'GET /api/image/civitai/credential': { saved: false },
      'POST /api/image/civitai/credential': { saved: false },
    });
    type('input[autocomplete="off"]', 'sk-secret');
    type('input[autocomplete="current-password"]', 'hunter2');
    click('Save key');
    await settle();

    expect(text()).toContain('Could not save the API key.');
    expect(text()).not.toContain('API key saved.');
    expect(container.querySelector('input[autocomplete="off"]')).not.toBeNull();
  });

  it('says what the computer said when the password is wrong', async () => {
    await open({}, {
      'GET /api/image/civitai/credential': { saved: false },
      'POST /api/image/civitai/credential': refuse(401, 'Current password is incorrect'),
    });

    type('input[autocomplete="off"]', 'sk-secret');
    type('input[autocomplete="current-password"]', 'nope');
    click('Save key');
    await settle();

    expect(text()).toContain('Current password is incorrect');
    expect(container.querySelector('input[autocomplete="off"]')).not.toBeNull();
  });

  it('sends the 2FA code when there is one', async () => {
    await open({ totpEnabled: true }, {
      'GET /api/image/civitai/credential': { saved: false },
      'POST /api/image/civitai/credential': { saved: true },
    });

    type('input[autocomplete="off"]', 'sk-secret');
    type('input[autocomplete="current-password"]', 'hunter2');
    type('input[inputmode="numeric"]', '654321');
    click('Save key');
    await settle();

    expect(posts('/api/image/civitai/credential')[0].body).toMatchObject({ totpCode: '654321' });
  });

  it('can be replaced when one is saved', async () => {
    await open();
    expect(text()).toContain('API key saved.');
    click('Replace');
    expect(container.querySelector('input[autocomplete="off"]')).not.toBeNull();
  });
});
