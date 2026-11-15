// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Realism step (desktop realism_step.dart): it opens on the
// saved character's own Realism values, shows the engine switch as the card
// has it, carries the Needs editor, shows the intimate rows only with 18+
// themes on, and saves a change once typing pauses — the Realism values
// alone, so the greetings and profile saved earlier are not sent back. The
// wizard is told while a change waits or saves.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
type Listener = (e: { event: string; characterId?: string; error?: string }) => void;
const listeners: Listener[] = [];
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: Listener) {
      listeners.push(cb);
    }
    connect() {}
    close() {}
  },
}));

import { RealismStep, type RealismStepHandle } from './RealismStep';

let host: HTMLDivElement;
let root: Root;
let detail: Record<string, unknown>;
let adult = false;
let outfit: { changed: boolean; reading: boolean; error: string | null };

const saved = () =>
  post.mock.calls.filter(([path]) => path === '/api/characters/c1').map(([, body]) => body as Record<string, unknown>);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  vi.useFakeTimers();
  adult = false;
  listeners.length = 0;
  outfit = { changed: false, reading: false, error: null };
  detail = {
    realismEnabled: true,
    occupation: 'lighthouse keeper',
    likes: ['salt wind'],
    intimateInto: ['slow kisses'],
    needsSimEnabled: true,
    greetingSeeds: [{ characterEmotion: 'calm' }],
  };
  get.mockReset();
  post.mockReset();
  get.mockImplementation((path: string) => {
    if (path === '/api/characters/c1/detail') return Promise.resolve({ realism: detail });
    if (path === '/api/chargen/outfit?characterId=c1') return Promise.resolve(outfit);
    if (path === '/api/settings') {
      return Promise.resolve({ realism: { adultThemesEnabled: adult, nsfwCooldownDefault: false } });
    }
    return Promise.resolve({});
  });
  post.mockResolvedValue({ ok: true });
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.useRealTimers();
});

async function mount(onWritingChange?: (w: boolean) => void) {
  const ref = createRef<RealismStepHandle>();
  await act(async () => {
    root.render(createElement(RealismStep, { ref, characterId: 'c1', onWritingChange }));
  });
  await act(async () => {
    await Promise.resolve();
  });
  return ref;
}

const engine = () =>
  [...host.querySelectorAll<HTMLLabelElement>('label.realism-toggle')].find((l) =>
    l.textContent?.includes('Enable Realism Engine'),
  )!.querySelector('input')!;

it('opens on the saved card: title, paragraph, its values, Needs inside', async () => {
  await mount();
  const text = host.textContent ?? '';
  expect(host.querySelector('h2')?.textContent).toBe('Porch Life');
  expect(text).toContain(
    'Wardrobe, likes, the story clock and Chaos work with or without the Realism Engine.',
  );
  expect(engine().checked).toBe(true);
  expect(text).toContain('Needs Simulation');
  expect(text).toContain('salt wind');
  expect((host.querySelector<HTMLInputElement>('input[value="lighthouse keeper"]'))).not.toBeNull();
});

it("shows the card's own engine value (the creator saved it at Porch Life's default)", async () => {
  detail.realismEnabled = false;
  await mount();
  expect(engine().checked).toBe(false);
  // With the engine off the bond and Needs rows wait, as on the desktop.
  expect(host.textContent).not.toContain('Needs Simulation');
});

it('shows the intimate rows only with 18+ themes on', async () => {
  await mount();
  expect(host.textContent).not.toContain('Intimate preferences');
  act(() => root.unmount());
  root = createRoot(host);
  adult = true;
  await mount();
  expect(host.textContent).toContain('Intimate preferences');
  expect(host.textContent).toContain('slow kisses');
});

it('saves a change once typing pauses: the Realism values only, then holds the wizard until done', async () => {
  const writing: boolean[] = [];
  await mount((w) => writing.push(w));
  await act(async () => {
    engine().click();
  });
  expect(writing.at(-1)).toBe(true);
  expect(saved()).toHaveLength(0);
  await act(async () => {
    vi.advanceTimersByTime(800);
  });
  await act(async () => {
    await Promise.resolve();
  });
  const body = saved().at(-1)!;
  expect(body.realismEnabled).toBe(false);
  expect(body.occupation).toBe('lighthouse keeper');
  // Not the greetings, the profile, or the greeting starting states.
  for (const k of ['firstMessage', 'alternateGreetings', 'description', 'name', 'greetingSeeds']) {
    expect(body, k).not.toHaveProperty(k);
  }
  expect(writing.at(-1)).toBe(false);
});

it('flush writes a waiting change at once (leaving the wizard)', async () => {
  const ref = await mount();
  await act(async () => {
    engine().click();
  });
  await act(async () => {
    await ref.current!.flush();
  });
  expect(saved()).toHaveLength(1);
  // Nothing left to write: a second flush sends nothing.
  await act(async () => {
    await ref.current!.flush();
  });
  expect(saved()).toHaveLength(1);
});

it('keeps a change that failed to save, and says so', async () => {
  post.mockRejectedValueOnce(new Error('offline'));
  const ref = await mount();
  await act(async () => {
    engine().click();
  });
  await act(async () => {
    await ref.current!.flush();
  });
  expect(host.querySelector('[role="alert"]')?.textContent).toContain('could not be saved');
  await act(async () => {
    await ref.current!.flush();
  });
  expect(saved()).toHaveLength(2);
  expect(saved()[1].realismEnabled).toBe(false);
});

// ── The outfit hint (#370) ─────────────────────────────────────────────

const hint = () => host.querySelector('[data-testid="outfit-hint"]');
const button = (label: string) =>
  [...host.querySelectorAll('button')].find((b) => b.textContent === label)!;
const emit = async (e: Parameters<Listener>[0]) => {
  await act(async () => {
    for (const l of listeners) l(e);
  });
  await act(async () => {
    await Promise.resolve();
  });
};

it('shows no outfit hint while the first message is the one the outfit was read from', async () => {
  await mount();
  expect(hint()).toBeNull();
});

it('a changed first message raises the hint above Pockets & Wardrobe; Re-read holds the wizard and brings the new outfit', async () => {
  outfit = { changed: true, reading: false, error: null };
  detail.inventory = { worn: [{ name: 'wool coat' }], carrying: [] };
  const writing: boolean[] = [];
  await mount((w) => writing.push(w));
  expect(hint()?.textContent).toContain('The first message changed');
  expect(hint()?.textContent).toContain('The outfit below was set from the old first message. Nothing was changed for you.');
  // Right above the wardrobe, as the desktop draws it.
  const heads = [...host.querySelectorAll('h4')].map((h) => h.textContent);
  const after = hint()!.nextElementSibling as HTMLElement;
  expect(after.textContent).toBe('Pockets & Wardrobe');
  expect(heads).toContain('Pockets & Wardrobe');

  await act(async () => {
    button('Re-read the outfit from it').click();
  });
  expect(post).toHaveBeenCalledWith('/api/chargen/outfit/reread', { characterId: 'c1' });
  expect(button('Reading the outfit…').disabled).toBe(true);
  expect(writing.at(-1)).toBe(true);

  detail.inventory = { worn: [{ name: 'rain slicker' }], carrying: [] };
  outfit = { changed: false, reading: false, error: null };
  await emit({ event: 'chargen_outfit_done', characterId: 'c1' });
  expect(hint()).toBeNull();
  expect(host.textContent).toContain('rain slicker');
  expect(writing.at(-1)).toBe(false);
});

it('a re-read with no answer keeps the hint and says why', async () => {
  outfit = { changed: true, reading: false, error: null };
  await mount();
  await act(async () => {
    button('Re-read the outfit from it').click();
  });
  await emit({ event: 'chargen_outfit_error', characterId: 'c1', error: 'Nothing was changed. Try again.' });
  expect(hint()).not.toBeNull();
  expect(hint()?.querySelector('[role="alert"]')?.textContent).toContain('Nothing was changed');
  expect(button('Re-read the outfit from it').disabled).toBe(false);
});

it('Keep this outfit settles the hint', async () => {
  outfit = { changed: true, reading: false, error: null };
  post.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/chargen/outfit/keep' ? { changed: false, reading: false, error: null } : { ok: true }),
  );
  await mount();
  await act(async () => {
    button('Keep this outfit').click();
  });
  await act(async () => {
    await Promise.resolve();
  });
  expect(post).toHaveBeenCalledWith('/api/chargen/outfit/keep', { characterId: 'c1' });
  expect(hint()).toBeNull();
});
