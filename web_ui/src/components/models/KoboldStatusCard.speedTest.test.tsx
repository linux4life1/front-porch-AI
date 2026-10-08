// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The speed test on the phone's Local model card, as the desktop's
// KoboldSpeedTestButton shows it: a button in auto mode only, on a host that
// sends `speedTest`; greyed with the host's reason under it when it cannot
// run; how the last test of the model ended under it, as a plain note; and,
// while a test runs, "Testing speed settings…", which opens it again. Renders
// the real card; the host's answers are the facade's shapes and words.

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
import type { SpeedTestCard } from './types';

const IDLE: SpeedTestCard = { state: 'idle', step: 0, steps: 0, left: null, doing: '', line: null, unavailable: null };

const AUTO: LocalModel = {
  model: '/m/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf',
  modelName: 'Qwen3.6 35B A3B',
  running: true,
  phase: 'ready',
  preset: null,
  auto: {
    lines: ['Set up for this computer automatically. The model is bigger than your graphics card, so replies come at about reading pace.'],
    context: 16384,
    choices: [8192, 16384, 32768],
    largestGood: 32768,
    verdicts: { '16384': { outcome: 'likeNow', title: 'Works like now.', text: 'Nothing else changes.' } },
  },
  presets: [{ path: '/k/Long chats.kcpps', name: 'Long chats', line: '32k chat · fitted to the card · smart cache off' }],
  speedTest: IDLE,
};

const ASK = 'This takes about 4 minutes. Replies may start sooner afterwards. Run it?';
const LABEL = 'Find the fastest settings for this computer';

let container: HTMLDivElement;
let root: Root;
let card: LocalModel;

async function show(c: LocalModel) {
  card = c;
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError: () => {} }));
  });
}

const $ = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const speedButton = () => $('speed-test-button') as HTMLButtonElement | null;

/** A plain note: not the red error line, not an alert, not a warning box. */
const plain = (el: HTMLElement) =>
  !el.closest('.error, .kc-verdict, [role="alert"]') && !/error|bad|warn/.test(el.className);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  sockets.length = 0;
  get.mockImplementation(async (path: string) => {
    if (path === '/api/backend/local-model') return card;
    if (path === '/api/backend/local-model/speed-test') return { ask: ASK, refused: null };
    throw new Error(`unexpected GET ${path}`);
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the speed test button on the Local model card', () => {
  it('is there in auto mode on a host that sends the speed test, and the hub is followed', async () => {
    await show(AUTO);
    const button = speedButton()!;
    expect(button.textContent).toBe(LABEL);
    expect(button.disabled).toBe(false);
    // In the auto section, under the context.
    expect($('local-model-card')!.contains(button)).toBe(true);
    expect(sockets.filter((s) => !s.closed)).toHaveLength(1);
  });

  it('is not there on a host without the speed test, and no socket is opened for it', async () => {
    await show({ ...AUTO, speedTest: undefined });
    expect($('local-model-card')).not.toBeNull();
    expect(speedButton()).toBeNull();
    expect(sockets).toHaveLength(0);
  });

  it('is not there while a preset is in use: the test tunes the app’s own settings', async () => {
    await show({
      ...AUTO,
      auto: null,
      preset: { path: '/k/Long chats.kcpps', name: 'Long chats', words: 'Loads Qwen3.6 35B A3B.' },
      speedTest: { ...IDLE, unavailable: "A preset is in use. The speed test tunes the app's own settings." },
    });
    expect(container.textContent).toContain('Uses your preset “Long chats”.');
    expect(speedButton()).toBeNull();
    expect($('speed-test-unavailable')).toBeNull();
  });

  it('is not there before the card knows how the model runs', async () => {
    await show({ ...AUTO, model: '', modelName: null, auto: null });
    expect(container.textContent).toContain('Choose a model below');
    expect(speedButton()).toBeNull();
  });

  it('is greyed when the test cannot run, with the host’s reason under it as a plain note', async () => {
    await show({ ...AUTO, speedTest: { ...IDLE, unavailable: 'Start the model first, then run the test.' } });
    const button = speedButton()!;
    expect(button.textContent).toBe(LABEL);
    expect(button.disabled).toBe(true);
    const why = $('speed-test-unavailable')!;
    expect(why.textContent).toBe('Start the model first, then run the test.');
    expect(plain(why)).toBe(true);
    expect(button.getAttribute('aria-describedby')).toBe(why.id);

    await act(async () => {
      button.click();
    });
    expect(get).not.toHaveBeenCalledWith('/api/backend/local-model/speed-test');
    expect($('speed-test-overlay')).toBeNull();
  });

  it('says how the last test of this model ended under the button, in plain text', async () => {
    await show({ ...AUTO, speedTest: { ...IDLE, state: 'done', step: 6, steps: 6, line: 'Replies now come about 17% sooner.' } });
    const line = $('speed-test-card-line')!;
    expect(line.textContent).toBe('Replies now come about 17% sooner.');
    expect(plain(line)).toBe(true);
    expect(speedButton()!.compareDocumentPosition(line) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(speedButton()!.disabled).toBe(false);
  });

  it('a test that stopped or failed is a plain note too, not an error', async () => {
    await show({ ...AUTO, speedTest: { ...IDLE, state: 'stopped', line: 'Stopped. Your settings were not changed.' } });
    expect(plain($('speed-test-card-line')!)).toBe(true);

    act(() => root.unmount());
    root = createRoot(container);
    await show({
      ...AUTO,
      speedTest: {
        ...IDLE,
        state: 'failed',
        line: 'The speed test stopped before it finished. Your settings were not changed.',
      },
    });
    expect($('speed-test-card-line')!.textContent).toBe(
      'The speed test stopped before it finished. Your settings were not changed.',
    );
    expect(plain($('speed-test-card-line')!)).toBe(true);
  });

  it('while a test runs it says so, and opens the test again without asking', async () => {
    await show({
      ...AUTO,
      speedTest: {
        state: 'running',
        step: 3,
        steps: 6,
        left: 'about 2 minutes',
        doing: 'Loading the model with other settings, then timing it…',
        line: 'Replies now come about 17% sooner.',
        // The host's reason not to start another: the button opens this one.
        unavailable: 'A speed test is already running.',
      },
    });
    const button = speedButton()!;
    expect(button.textContent).toBe('Testing speed settings…');
    expect(button.disabled).toBe(false);
    expect($('speed-test-unavailable')).toBeNull();
    expect($('speed-test-card-line')).toBeNull();

    await act(async () => {
      button.click();
    });
    expect(get).not.toHaveBeenCalledWith('/api/backend/local-model/speed-test');
    expect($('speed-test-overlay')).not.toBeNull();
    expect($('speed-test-step')!.textContent).toBe('Step 3 of 6');
    expect($('speed-test-left')!.textContent).toBe('About 2 minutes left');
  });

  it('turns to "Testing speed settings…" when the hub says a test started elsewhere', async () => {
    await show(AUTO);
    await act(async () => {
      sockets[0].emit({
        event: 'speed_test',
        speedTest: { state: 'running', step: 0, steps: 0, left: 'less than a minute', doing: 'Waiting for KoboldCpp to finish what it is doing…', line: null },
      });
    });
    expect(speedButton()!.textContent).toBe('Testing speed settings…');
  });

  it('names no setting anywhere: no batch, MMQ, mmap or flash, on the card or in the test', async () => {
    const machinery = /batch|mmq|mmap|flash/i;
    await show({ ...AUTO, speedTest: { ...IDLE, state: 'done', line: 'Replies now come about 17% sooner.' } });
    expect(container.textContent).not.toMatch(machinery);

    await act(async () => {
      speedButton()!.click();
    });
    expect($('speed-test-ask')!.textContent).toBe(ASK);
    expect(container.textContent).not.toMatch(machinery);

    post.mockResolvedValue({ started: true, refused: null });
    await act(async () => {
      ($('speed-test-run') as HTMLButtonElement).click();
    });
    await act(async () => {
      sockets[0].emit({
        event: 'speed_test',
        speedTest: { state: 'running', step: 2, steps: 6, left: 'about 3 minutes', doing: 'Loading the model with other settings, then timing it…', line: null },
      });
    });
    expect($('speed-test-progress')).not.toBeNull();
    expect(container.textContent).not.toMatch(machinery);

    const ended = { state: 'done', step: 6, steps: 6, left: null, doing: '', line: 'Your current settings were already the fastest.' } as const;
    card = { ...AUTO, speedTest: { ...ended, unavailable: null } };
    await act(async () => {
      sockets[0].emit({ event: 'speed_test', speedTest: ended });
    });
    expect($('speed-test-line')!.textContent).toBe('Your current settings were already the fastest.');
    expect(container.textContent).not.toMatch(machinery);
  });
});
