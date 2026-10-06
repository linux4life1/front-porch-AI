// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's speed test overlay, driven through the real Local model card
// the way a person uses it, as the desktop's showKoboldSpeedTest runs it:
// tap, the host's question, Run it, the hub's progress, Cancel, the end
// line and Done. Every sentence is the host's (the facade's words); the
// phone adds only the desktop's labels. The host's answers are mocked at
// the client module, as the card's other tests do.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { WsEvent } from '../../api/ws';

const { get, post, sockets } = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  sockets: [] as { emit: (e: WsEvent) => void; closed: boolean }[],
}));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    entry: { emit: (e: WsEvent) => void; closed: boolean };
    constructor(onEvent: (e: WsEvent) => void) {
      this.entry = { emit: onEvent, closed: false };
      sockets.push(this.entry);
    }
    connect() {}
    close() {
      this.entry.closed = true;
    }
  },
}));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';
import type { SpeedTestCard, SpeedTestRun } from './types';

const IDLE: SpeedTestCard = { state: 'idle', step: 0, steps: 0, left: null, doing: '', line: null, unavailable: null };
const RUNNING: SpeedTestRun = {
  state: 'running',
  step: 2,
  steps: 6,
  left: 'about 3 minutes',
  doing: 'Loading the model with other settings, then timing it…',
  line: null,
};
const STOPPING: SpeedTestRun = { ...RUNNING, state: 'stopping', doing: 'Stopping after this step…' };
const DONE: SpeedTestRun = { state: 'done', step: 6, steps: 6, left: null, doing: '', line: 'Replies now come about 17% sooner.' };

const AUTO: LocalModel = {
  model: '/m/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  modelName: 'Llama 3.2 3B',
  running: true,
  phase: 'ready',
  preset: null,
  auto: {
    lines: ['Set up for this computer automatically. The whole model fits on your graphics card.'],
    context: 16384,
    choices: [8192, 16384, 32768],
    largestGood: 32768,
    verdicts: { '16384': { outcome: 'likeNow', title: 'Works like now.', text: 'Nothing else changes.' } },
  },
  presets: [],
  speedTest: IDLE,
};

const ASK = 'This takes about 4 minutes. Replies may start sooner afterwards. Run it?';
const LABEL = 'Find the fastest settings for this computer';

/** The phone's own words when the computer does not answer (chatActionError). */
const unreachable = (what: string) =>
  `Couldn't ${what}. Front Porch AI didn't answer — check the app is still open on your computer and this device is on the same network, then try again.`;

let container: HTMLDivElement;
let root: Root;
let card: LocalModel;
let ask: { ask: string | null; refused: string | null };

const settle = () =>
  act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });

async function show(c: LocalModel) {
  card = c;
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError: () => {} }));
  });
  await settle();
}

const $ = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const overlay = () => $('speed-test-overlay');
const labels = (el: Element) => Array.from(el.querySelectorAll('button')).map((b) => b.textContent);
const tap = async (id: string) => {
  await act(async () => {
    ($(id) as HTMLButtonElement).click();
  });
  await settle();
};
const hub = async (e: WsEvent) => {
  await act(async () => {
    sockets.filter((s) => !s.closed)[0].emit(e);
  });
  await settle();
};
const progress = (run: SpeedTestRun) => hub({ event: 'speed_test', speedTest: run });
const escape = () =>
  act(async () => {
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
  });
const tapOutside = () =>
  act(async () => {
    (container.querySelector('.kc-speed-overlay') as HTMLElement).click();
  });
const cardReads = () => get.mock.calls.filter(([p]) => p === '/api/backend/local-model').length;

/** Tap the button, and Run it at the host's question. */
async function runIt() {
  await tap('speed-test-button');
  post.mockResolvedValueOnce({ started: true, refused: null });
  await tap('speed-test-run');
}

function deferred<T>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  sockets.length = 0;
  ask = { ask: ASK, refused: null };
  get.mockImplementation(async (path: string) => {
    if (path === '/api/backend/local-model') return card;
    if (path === '/api/backend/local-model/speed-test') return ask;
    throw new Error(`unexpected GET ${path}`);
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the speed test overlay', () => {
  it('asks the host first, with how long it takes; Run it starts the test', async () => {
    await show(AUTO);
    await tap('speed-test-button');

    expect(get).toHaveBeenCalledWith('/api/backend/local-model/speed-test');
    const dialog = overlay()!;
    expect(dialog.getAttribute('role')).toBe('dialog');
    expect(dialog.getAttribute('aria-modal')).toBe('true');
    expect(document.getElementById(dialog.getAttribute('aria-labelledby')!)!.textContent).toBe(
      'Find the fastest settings',
    );
    expect($('speed-test-ask')!.textContent).toBe(ASK);
    expect(labels(dialog)).toEqual(['Not now', 'Run it']);
    expect(dialog.contains(document.activeElement)).toBe(true);
    expect(post).not.toHaveBeenCalled();

    post.mockResolvedValueOnce({ started: true, refused: null });
    await tap('speed-test-run');
    expect(post.mock.calls).toEqual([['/api/backend/local-model/speed-test']]);
    expect($('speed-test-ask')).toBeNull();
    expect($('speed-test-progress')).not.toBeNull();
  });

  it('a second tap while the question is on its way asks only once', async () => {
    await show(AUTO);
    const asked = deferred<{ ask: string | null; refused: string | null }>();
    get.mockImplementationOnce(() => asked.promise);
    await tap('speed-test-button');
    // Not greyed meanwhile: a greyed button would drop the focus it gets back.
    expect(($('speed-test-button') as HTMLButtonElement).disabled).toBe(false);
    await tap('speed-test-button');
    expect(get.mock.calls.filter(([p]) => p === '/api/backend/local-model/speed-test')).toHaveLength(1);

    await act(async () => {
      asked.resolve({ ask: ASK, refused: null });
    });
    await settle();
    expect($('speed-test-ask')!.textContent).toBe(ASK);
  });

  it('Not now, a tap outside and Escape each close the question, and nothing starts', async () => {
    await show(AUTO);
    const button = $('speed-test-button') as HTMLButtonElement;
    button.focus();
    await tap('speed-test-button');
    await tap('speed-test-not-now');
    expect(overlay()).toBeNull();
    expect(document.activeElement).toBe(button);

    await tap('speed-test-button');
    await tapOutside();
    expect(overlay()).toBeNull();

    await tap('speed-test-button');
    await escape();
    expect(overlay()).toBeNull();
    expect(post).not.toHaveBeenCalled();
  });

  it('when the host says no at the question, it says why, with Close only', async () => {
    ask = { ask: null, refused: 'This computer is still being looked at. Try again in a moment.' };
    await show(AUTO);
    await tap('speed-test-button');

    expect($('speed-test-refused')!.textContent).toBe('This computer is still being looked at. Try again in a moment.');
    expect(labels(overlay()!)).toEqual(['Close']);
    expect($('speed-test-run')).toBeNull();
    await tap('speed-test-close');
    expect(overlay()).toBeNull();
    expect(post).not.toHaveBeenCalled();
  });

  it('when the host will not start it, it says why, and the card is not left saying it runs', async () => {
    await show(AUTO);
    await tap('speed-test-button');
    const before = cardReads();
    post.mockResolvedValueOnce({ started: false, refused: 'A speed test is already running.' });
    await tap('speed-test-run');

    expect($('speed-test-refused')!.textContent).toBe('A speed test is already running.');
    expect(labels(overlay()!)).toEqual(['Close']);
    expect(cardReads()).toBe(before + 1);
    expect($('speed-test-button')!.textContent).toBe(LABEL);
  });

  it('follows the hub: the step, the time left, what it does, and a bar of the steps done', async () => {
    await show(AUTO);
    await runIt();
    await progress(RUNNING);

    expect($('speed-test-step')!.textContent).toBe('Step 2 of 6');
    expect($('speed-test-left')!.textContent).toBe('About 3 minutes left');
    expect($('speed-test-doing')!.textContent).toBe('Loading the model with other settings, then timing it…');
    const bar = $('speed-test-progress')!;
    expect(bar.getAttribute('role')).toBe('progressbar');
    // As the desktop's bar: the steps finished, one before the one under way.
    expect(bar.getAttribute('aria-valuemin')).toBe('0');
    expect(bar.getAttribute('aria-valuemax')).toBe('6');
    expect(bar.getAttribute('aria-valuenow')).toBe('1');
    expect(bar.getAttribute('aria-valuetext')).toBe('Step 2 of 6');
    expect((bar.firstElementChild as HTMLElement).style.width).toMatch(/^16\.66/);
    expect(labels(overlay()!)).toEqual(['Cancel']);

    // It stays up while the test runs.
    await tapOutside();
    await escape();
    expect(overlay()).not.toBeNull();
    expect($('speed-test-button')!.textContent).toBe('Testing speed settings…');
  });

  it('before the host knows the steps it says Getting ready, and never shows the last test’s line', async () => {
    await show({ ...AUTO, speedTest: { ...IDLE, state: 'done', steps: 6, step: 6, line: 'Your current settings were already the fastest.' } });
    await runIt();

    expect($('speed-test-step')!.textContent).toBe('Getting ready');
    expect($('speed-test-left')).toBeNull();
    expect($('speed-test-line')).toBeNull();
    expect($('speed-test-done')).toBeNull();
    expect(overlay()!.textContent).not.toContain('already the fastest');
    expect($('speed-test-progress')!.hasAttribute('aria-valuenow')).toBe(false);

    await progress({
      state: 'running',
      step: 0,
      steps: 0,
      left: 'less than a minute',
      doing: 'Waiting for KoboldCpp to finish what it is doing…',
      line: 'Your current settings were already the fastest.',
    });
    expect($('speed-test-step')!.textContent).toBe('Getting ready');
    expect($('speed-test-left')).toBeNull();
    expect($('speed-test-doing')!.textContent).toBe('Waiting for KoboldCpp to finish what it is doing…');
    expect(overlay()!.textContent).not.toContain('already the fastest');
  });

  it('Cancel asks the host to stop; while it stops, Cancel waits', async () => {
    await show(AUTO);
    await runIt();
    await progress(RUNNING);
    post.mockResolvedValueOnce({ ok: true });
    await tap('speed-test-cancel');
    expect(post).toHaveBeenLastCalledWith('/api/backend/local-model/speed-test/cancel');

    await progress(STOPPING);
    expect($('speed-test-doing')!.textContent).toBe('Stopping after this step…');
    expect(($('speed-test-cancel') as HTMLButtonElement).disabled).toBe(true);
  });

  it('a Cancel that does not reach the computer says so in plain words, and Cancel can be tapped again', async () => {
    await show(AUTO);
    await runIt();
    await progress(RUNNING);
    // What Chromium's fetch throws when the computer cannot be reached.
    post.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    await tap('speed-test-cancel');

    const problem = $('speed-test-problem')!;
    expect(problem.getAttribute('role')).toBe('alert');
    expect(problem.textContent).toBe(unreachable('stop the speed test'));
    expect(($('speed-test-cancel') as HTMLButtonElement).disabled).toBe(false);

    post.mockResolvedValueOnce({ ok: true });
    await tap('speed-test-cancel');
    expect(post).toHaveBeenLastCalledWith('/api/backend/local-model/speed-test/cancel');
    expect($('speed-test-problem')).toBeNull();
  });

  it('when the computer cannot be reached at the question or at Run it, it says so in plain words, not the browser’s', async () => {
    await show(AUTO);
    // WebKit's words for the same failure.
    get.mockRejectedValueOnce(new TypeError('Load failed'));
    await tap('speed-test-button');
    expect($('speed-test-refused')!.textContent).toBe(unreachable('open the speed test'));
    expect(labels(overlay()!)).toEqual(['Close']);

    // Close, and the button asks again.
    await tap('speed-test-close');
    await tap('speed-test-button');
    expect($('speed-test-ask')!.textContent).toBe(ASK);

    post.mockRejectedValueOnce(new TypeError('Failed to fetch'));
    await tap('speed-test-run');
    expect($('speed-test-refused')!.textContent).toBe(unreachable('start the speed test'));
    expect(labels(overlay()!)).toEqual(['Close']);
    expect($('speed-test-button')!.textContent).toBe(LABEL);
    expect(container.textContent).not.toMatch(/Failed to fetch|Load failed/);
  });

  it('ends with the one line and Done; the card reads itself again and shows the line', async () => {
    await show(AUTO);
    await runIt();
    await progress(RUNNING);
    const before = cardReads();
    card = { ...AUTO, speedTest: { ...DONE, unavailable: null } };
    await progress(DONE);

    expect($('speed-test-line')!.textContent).toBe('Replies now come about 17% sooner.');
    expect($('speed-test-line')!.closest('.error, .kc-verdict, [role="alert"]')).toBeNull();
    expect(labels(overlay()!)).toEqual(['Done']);
    expect($('speed-test-progress')).toBeNull();
    expect(cardReads()).toBe(before + 1);
    expect($('speed-test-card-line')!.textContent).toBe('Replies now come about 17% sooner.');

    await tap('speed-test-done');
    expect(overlay()).toBeNull();
    const button = $('speed-test-button') as HTMLButtonElement;
    expect(button.textContent).toBe(LABEL);
    expect(button.disabled).toBe(false);
  });

  it('a test stopped by Cancel ends with its own line', async () => {
    await show(AUTO);
    await runIt();
    await progress(STOPPING);
    const stopped: SpeedTestRun = { ...STOPPING, state: 'stopped', left: null, doing: '', line: 'Stopped. Your settings were not changed.' };
    card = { ...AUTO, speedTest: { ...stopped, unavailable: null } };
    await progress(stopped);

    expect($('speed-test-line')!.textContent).toBe('Stopped. Your settings were not changed.');
    expect($('speed-test-line')!.closest('.error, .kc-verdict, [role="alert"]')).toBeNull();
    expect(labels(overlay()!)).toEqual(['Done']);
  });

  it('a card read sent before the hub’s latest word does not undo it; one sent after it does', async () => {
    await show(AUTO);
    await runIt();
    await progress(RUNNING);

    const late = deferred<LocalModel>();
    get.mockImplementationOnce(() => late.promise);
    await hub({ event: 'connected' }); // the card is read again on a reconnect
    await progress(STOPPING);
    await act(async () => {
      late.resolve({ ...AUTO, speedTest: { ...RUNNING, unavailable: 'A speed test is already running.' } });
    });
    await settle();
    expect($('speed-test-doing')!.textContent).toBe('Stopping after this step…');
    expect(($('speed-test-cancel') as HTMLButtonElement).disabled).toBe(true);

    card = { ...AUTO, speedTest: { ...DONE, line: 'Stopped. Your settings were not changed.', state: 'stopped', unavailable: null } };
    await hub({ event: 'connected' });
    expect($('speed-test-line')!.textContent).toBe('Stopped. Your settings were not changed.');
  });

  it('an older card read that lands after a newer one is dropped', async () => {
    await show(AUTO);
    const older = deferred<LocalModel>();
    const newer = deferred<LocalModel>();
    get.mockImplementationOnce(() => older.promise).mockImplementationOnce(() => newer.promise);
    await hub({ event: 'connected' });
    await hub({ event: 'connected' });

    await act(async () => {
      newer.resolve({ ...AUTO, speedTest: { ...DONE, unavailable: null } });
    });
    await act(async () => {
      older.resolve(AUTO);
    });
    await settle();
    expect($('speed-test-card-line')!.textContent).toBe('Replies now come about 17% sooner.');
  });
});
