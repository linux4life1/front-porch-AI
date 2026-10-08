// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat backend picker on the phone's Settings, on an Intel Mac host.
// KoboldCpp cannot run there: the desktop greys it out in its backend picker
// and says why (backend_mode_selector.dart: koboldEnabled: !isIntelMac, and
// kIntelMacLocalUnsupported above it). The phone offered it like any other
// backend. Now it is greyed out the same way, with the desktop's sentence
// beside it, while the host's status says local models cannot run.
//
// The host is only sure once it has read its processor, a moment after it
// starts, so the page follows every answer while it shows: an "unsupported"
// the host takes back gives KoboldCpp back, and one that comes late greys it
// out.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The rest of the page has its own tests; here it is only in the way.
vi.mock('../components/PersonaManager', () => ({ PersonaManager: () => null }));
vi.mock('../components/ModelPicker', () => ({ ModelPicker: () => null }));
vi.mock('../components/ChatColorsSettings', () => ({ ChatColorsSettings: () => null }));
vi.mock('../components/ReadingSizeSettings', () => ({ ReadingSizeSettings: () => null }));
vi.mock('../components/FollowStreamingSettings', () => ({ FollowStreamingSettings: () => null }));
vi.mock('../components/MessageSideSettings', () => ({ MessageSideSettings: () => null }));
vi.mock('../components/PorchLifeSettings', () => ({ PorchLifeSettings: () => null }));
vi.mock('../components/ModelTransportCard', () => ({ ModelTransportCard: () => null }));
vi.mock('../components/IdleUnloadSettings', async () => {
  const { createElement: h } = await import('react');
  return { IdleUnloadSettings: () => h('div', { 'data-testid': 'idle-unload' }) };
});
vi.mock('../components/GenerationSettingsFields', () => ({ GenerationSettingsFields: () => null }));
vi.mock('../components/VoiceMediaSettings', () => ({ VoiceMediaSettings: () => null }));
vi.mock('../components/WorkerBackendCard', () => ({ WorkerBackendCard: () => null }));
vi.mock('../components/SuperGrokCard', () => ({ SuperGrokCard: () => null }));

import { SettingsPage } from './SettingsPage';
import { INTEL_MAC_LOCAL_UNSUPPORTED } from '../backendOptions';

/** What the host says now. Undefined is an app too old to say. */
let unsupported: boolean | undefined;
/** The chat backend the host has saved. */
let backend: 'openRouter' | 'kobold';

const settings = () => ({
  backend,
  backends: ['kobold', 'openRouter', 'omlx'],
  isLocal: backend === 'kobold',
  loadedModel: backend === 'kobold' ? 'No model loaded' : 'Not set',
  remoteApiUrl: 'https://openrouter.ai/api/v1',
  remoteModelName: '',
  hasApiKey: false,
  contextSize: 16384,
  reasoningEnabled: false,
  reasoningEffort: 'medium',
  generation: {},
});

let container: HTMLDivElement;
let root: Root;

async function open() {
  get.mockImplementation((path: string) => {
    if (path === '/api/settings') return Promise.resolve(settings());
    if (path === '/api/backend/status') {
      return Promise.resolve(unsupported === undefined ? {} : { localUnsupported: unsupported });
    }
    return Promise.resolve({});
  });
  await act(async () => {
    root.render(createElement(SettingsPage));
  });
}

/** The chat speech card's Backend picker, its first select. */
const picker = () =>
  container.querySelector('[data-testid="chat-speech-card"] select') as HTMLSelectElement;
const option = (id: string) => picker().querySelector(`option[value="${id}"]`) as HTMLOptionElement;
const sentence = () => container.querySelector('[data-testid="chat-local-unsupported"]');
const idleUnload = () => container.querySelector('[data-testid="idle-unload"]');
const later = async () => {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(5500);
  });
};

beforeEach(() => {
  vi.useFakeTimers();
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  backend = 'openRouter';
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('the chat backend picker on an Intel Mac host', () => {
  it("greys KoboldCpp out and says why, in the desktop's words", async () => {
    unsupported = true;
    await open();

    expect(option('kobold').disabled).toBe(true);
    expect(sentence()?.textContent).toBe(INTEL_MAC_LOCAL_UNSUPPORTED);
    for (const remote of ['openrouter', 'nanogpt', 'xai', 'lmstudio', 'custom']) {
      expect(option(remote).disabled, remote).toBe(false);
    }
  });

  it.each([
    ['a host that can run it', false],
    ['an app too old to say', undefined],
  ])('on %s, KoboldCpp is a backend as before', async (_, answer) => {
    unsupported = answer;
    await open();

    expect(option('kobold').disabled).toBe(false);
    expect(sentence()).toBeNull();
  });

  // KoboldCpp is the app's first backend, so an Intel Mac that never changed
  // it has it saved. Its KoboldCpp-only parts of the page give way to the
  // sentence, as the Models page's cards do.
  it('a saved KoboldCpp stays shown, with the sentence instead of its Models tab pointer and idle unload card', async () => {
    backend = 'kobold';
    unsupported = true;
    await open();

    expect(picker().value).toBe('kobold');
    expect(sentence()?.textContent).toBe(INTEL_MAC_LOCAL_UNSUPPORTED);
    expect(container.textContent).not.toContain('Models tab');
    expect(idleUnload()).toBeNull();
  });

  it('on a host that can run it, a saved KoboldCpp keeps them', async () => {
    backend = 'kobold';
    unsupported = false;
    await open();

    expect(container.textContent).toContain('Models tab');
    expect(idleUnload()).not.toBeNull();
  });
});

describe('the chat backend picker while the host reads its processor', () => {
  it('an "unsupported" the host takes back gives KoboldCpp back', async () => {
    unsupported = true;
    await open();
    expect(option('kobold').disabled).toBe(true);

    unsupported = false;
    await later();

    expect(option('kobold').disabled).toBe(false);
    expect(sentence()).toBeNull();
  });

  it('an "unsupported" that comes late greys KoboldCpp out', async () => {
    unsupported = false;
    await open();
    expect(option('kobold').disabled).toBe(false);

    unsupported = true;
    await later();

    expect(option('kobold').disabled).toBe(true);
    expect(sentence()?.textContent).toBe(INTEL_MAC_LOCAL_UNSUPPORTED);
  });
});
