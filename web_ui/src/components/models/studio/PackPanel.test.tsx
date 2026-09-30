// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone starts an expression pack, watches it, stops it, and imports what
// it made. The computer decides how the pictures are made; the phone sends the
// choice and shows the answer, including why a pack cannot start.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import {
  button, click, container, createElement, field, gets, mount, posts, refuse, reset, serve, settle,
  text, unmount,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { PackPanel } = await import('./PackPanel');

afterEach(() => {
  unmount();
  reset();
  window.localStorage.clear();
});

const slot = (emotion: string, state: string, over: Record<string, unknown> = {}) => ({
  emotion,
  state,
  keep: true,
  error: null,
  ...over,
});

const view = (over: Record<string, unknown> = {}) => ({
  running: false,
  mode: 'edit',
  origin: 'phone',
  characterId: 'c1',
  characterName: 'Mara',
  total: 2,
  done: 2,
  kept: 2,
  imported: null,
  canImport: true,
  slots: [slot('joy', 'done'), slot('sadness', 'done')],
  ...over,
});

const characters = [
  { id: 'c1', name: 'Mara' },
  { id: 'c2', name: 'Bram' },
];

const boot = async (
  routes: Record<string, unknown> = {},
  props: Record<string, unknown> = {},
) => {
  serve({
    'GET /api/image/expression-pack': refuse(404, 'No expression pack'),
    'GET /api/characters': characters,
    ...routes,
  });
  const onNote = vi.fn();
  mount(createElement(PackPanel, { prompt: 'a woman on a porch', picture: null, onNote, ...props }));
  await settle();
  return onNote;
};

describe('starting a pack', () => {
  it('sends the character and the choices, and shows the pack that starts', async () => {
    await boot({ 'POST /api/image/expression-pack': view({ running: true, done: 0, canImport: false }) });

    click('Start pack');
    await settle();

    expect(posts('/api/image/expression-pack').map((c) => c.body)).toEqual([
      {
        characterId: 'c1',
        set: 'starter',
        skipExisting: true,
        replaceExisting: true,
        denoise: 0.7,
        prompt: 'a woman on a porch',
      },
    ]);
    expect(text()).toContain('Mara: 0 of 2 made — working…');
    expect(button('Start pack')!.disabled).toBe(true);
  });

  it('sends every choice that was changed', async () => {
    await boot({ 'POST /api/image/expression-pack': view() });

    const select = field<HTMLSelectElement>('select[aria-label="Character"]');
    act(() => {
      select.value = 'c2';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    click('Full (28)');
    const [keep, replace] = [...container.querySelectorAll<HTMLInputElement>('input[type="checkbox"]')];
    act(() => keep.click());
    act(() => replace.click());
    const slider = field<HTMLInputElement>('input[aria-label="Variation strength"]');
    act(() => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(slider, '0.5');
      slider.dispatchEvent(new Event('input', { bubbles: true }));
    });
    click('Start pack');
    await settle();

    expect(posts('/api/image/expression-pack')[0].body).toMatchObject({
      characterId: 'c2',
      set: 'full',
      skipExisting: false,
      replaceExisting: false,
      denoise: 0.5,
    });
    expect(window.localStorage.getItem('fpai.pack.character')).toBe('c2');
  });

  it('builds from a picture that was chosen, sent as it was chosen', async () => {
    await boot(
      { 'POST /api/image/expression-pack': view() },
      { picture: { kind: 'file', name: 'me.png', dataUrl: 'data:image/png;base64,AAAA' } },
    );
    expect(text()).toContain('Built from me.png.');
    click('Start pack');
    await settle();
    expect(posts('/api/image/expression-pack')[0].body).toMatchObject({
      referenceImage: 'data:image/png;base64,AAAA',
    });
    expect(posts('/api/image/expression-pack')[0].body).not.toHaveProperty('referenceFilename');
  });

  it('builds from a picture the computer saved, by its name', async () => {
    await boot(
      { 'POST /api/image/expression-pack': view() },
      { picture: { kind: 'saved', name: 'saved_1.png', url: '/api/image/saved/saved_1.png' } },
    );
    click('Start pack');
    await settle();
    expect(posts('/api/image/expression-pack')[0].body).toMatchObject({
      referenceFilename: 'saved_1.png',
    });
    expect(posts('/api/image/expression-pack')[0].body).not.toHaveProperty('referenceImage');
  });

  it('says why a pack cannot start, in the computer’s words, and shows no pack', async () => {
    const why = 'An expression pack on ComfyUI runs your Edit graph, and it is not ready: …';
    const onNote = await boot({ 'POST /api/image/expression-pack': refuse(409, why, { code: 'not_ready' }) });

    click('Start pack');
    await settle();

    expect(onNote).toHaveBeenCalledWith(why);
    expect(container.querySelector('[data-region="pack-status"]')).toBeNull();
    expect(button('Start pack')!.disabled).toBe(false);
  });

  it('cannot start without a character', async () => {
    await boot({ 'GET /api/characters': [] });
    expect(button('Start pack')!.disabled).toBe(true);
  });
});

describe('watching a pack', () => {
  it('shows each picture that is made, and only those', async () => {
    await boot({
      'GET /api/image/expression-pack': view({
        running: true,
        done: 1,
        canImport: false,
        slots: [slot('joy', 'done'), slot('sadness', 'generating'), slot('anger', 'failed', { error: 'out of memory' })],
        total: 3,
      }),
    });

    const pictures = [...container.querySelectorAll('img')];
    expect(pictures.map((i) => i.getAttribute('src'))).toEqual([
      '/api/image/expression-pack/picture?emotion=joy',
    ]);
    expect(text()).toContain('sadness: making');
    expect(text()).toContain('anger: failed — out of memory');
    expect(text()).toContain('Made with the Edit graph.');
  });

  it('says so when the engine has no Edit path', async () => {
    await boot({ 'GET /api/image/expression-pack': view({ mode: 'img2img' }) });
    expect(text()).toContain('no Edit path');
  });

  it('shows a picture the quality check flagged', async () => {
    await boot({
      'GET /api/image/expression-pack': view({
        slots: [
          slot('joy', 'done', {
            verdict: { samePerson: true, expressionMatches: false, note: 'looks flat' },
          }),
        ],
        total: 1,
        done: 1,
      }),
    });
    expect(text()).toContain('check: looks flat');
  });

  it('stops the pack', async () => {
    await boot({
      'GET /api/image/expression-pack': view({ running: true, canImport: false }),
      'POST /api/image/expression-pack/cancel': view({ running: false, canImport: false }),
    });

    click('Cancel pack');
    await settle();

    expect(posts('/api/image/expression-pack/cancel')).toHaveLength(1);
    expect(button('Cancel pack')).toBeUndefined();
  });

  it('follows the pack as it changes', async () => {
    vi.useFakeTimers();
    try {
      let n = 0;
      serve({
        'GET /api/image/expression-pack': () =>
          n++ === 0 ? view({ running: true, done: 0, canImport: false }) : view({ done: 2 }),
        'GET /api/characters': characters,
      });
      mount(createElement(PackPanel, { prompt: '', picture: null, onNote: vi.fn() }));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });
      expect(text()).toContain('0 of 2 made');

      await act(async () => {
        await vi.advanceTimersByTimeAsync(2100);
      });

      expect(text()).toContain('2 of 2 made');
      expect(gets('/api/image/expression-pack').length).toBeGreaterThan(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it('drops a pack the computer no longer has', async () => {
    vi.useFakeTimers();
    try {
      let n = 0;
      serve({
        'GET /api/image/expression-pack': () =>
          n++ === 0 ? view() : refuse(404, 'No expression pack'),
        'GET /api/characters': characters,
      });
      mount(createElement(PackPanel, { prompt: '', picture: null, onNote: vi.fn() }));
      await act(async () => {
        await vi.advanceTimersByTimeAsync(0);
      });
      expect(text()).toContain('Mara: 2 of 2 made');

      await act(async () => {
        await vi.advanceTimersByTimeAsync(2100);
      });

      expect(container.querySelector('[data-region="pack-status"]')).toBeNull();
    } finally {
      vi.useRealTimers();
    }
  });

  it('shows a pack the computer started, without offering to import it', async () => {
    await boot({ 'GET /api/image/expression-pack': view({ origin: 'desktop', canImport: false }) });
    expect(text()).toContain('Started on the computer.');
    expect(text()).toContain('Import it from Image Studio on the computer.');
    expect(button(/^Import/)).toBeUndefined();
  });
});

describe('importing', () => {
  it('imports the ones that are kept, leaving out the ones that were unticked', async () => {
    await boot({
      'GET /api/image/expression-pack': view(),
      'POST /api/image/expression-pack/import': view({ imported: 1, canImport: false }),
    });
    expect(button('Import 2 to Mara')).toBeDefined();

    act(() => field<HTMLInputElement>('input[aria-label="Keep sadness"]').click());
    expect(button('Import 1 to Mara')).toBeDefined();
    click('Import 1 to Mara');
    await settle();

    expect(posts('/api/image/expression-pack/import').map((c) => c.body)).toEqual([{ keep: ['joy'] }]);
    expect(text()).toContain('Imported 1 for Mara.');
    expect(button(/^Import/)).toBeUndefined();
  });

  it('cannot import with nothing kept', async () => {
    await boot({ 'GET /api/image/expression-pack': view() });
    act(() => field<HTMLInputElement>('input[aria-label="Keep joy"]').click());
    act(() => field<HTMLInputElement>('input[aria-label="Keep sadness"]').click());
    expect(button('Import 0 to Mara')!.disabled).toBe(true);
  });

  it('is not offered while pictures are still being made', async () => {
    await boot({ 'GET /api/image/expression-pack': view({ running: true, canImport: false }) });
    expect(button(/^Import/)).toBeUndefined();
    expect(container.querySelector('input[aria-label="Keep joy"]')).toBeNull();
  });

  it('says what went wrong', async () => {
    const onNote = await boot({
      'GET /api/image/expression-pack': view(),
      'POST /api/image/expression-pack/import': refuse(409, 'Those pictures are already imported.'),
    });
    click('Import 2 to Mara');
    await settle();
    expect(onNote).toHaveBeenCalledWith('Those pictures are already imported.');
  });
});
