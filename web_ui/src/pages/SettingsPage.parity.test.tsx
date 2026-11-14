// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SETTINGS PARITY — WEB SIDE. docs/design/settings-parity-manifest.json maps
// every Settings control to its home on each surface. This guard proves the
// web half: SettingsPage offers the seven desktop tabs in order and shows one
// section at a time, and each control sits in its pinned section (the grouped
// controls also inside their group). The desktop half is guarded by
// test/hygiene/settings_parity_manifest_test.dart. Move a card in the page
// without the manifest, and this fails.

import { readFileSync } from 'node:fs';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

// Each sub-panel is a stub carrying the marker text its real component
// renders (and its testid). The panels have their own tests; here only the
// page's wiring is under test. PromptSettingsCard stays real — its markers
// are the point of the Phase 2 move.
vi.mock('../components/PersonaManager', async () => {
  const { createElement: h } = await import('react');
  return { PersonaManager: () => h('div', { 'data-testid': 'persona-manager' }, 'User personas') };
});
vi.mock('../components/MessageSideSettings', async () => {
  const { createElement: h } = await import('react');
  return { MessageSideSettings: () => h('div', { 'data-testid': 'message-side-card' }, 'My messages on the right') };
});
vi.mock('../components/FollowStreamingSettings', async () => {
  const { createElement: h } = await import('react');
  return { FollowStreamingSettings: () => h('div', { 'data-testid': 'follow-streaming-card' }, 'Follow streaming replies') };
});
vi.mock('../components/ReadingSizeSettings', async () => {
  const { createElement: h } = await import('react');
  return { ReadingSizeSettings: () => h('div', { 'data-testid': 'reading-size-card' }, 'Reading size') };
});
vi.mock('../components/ChatColorsSettings', async () => {
  const { createElement: h } = await import('react');
  return { ChatColorsSettings: () => h('div', { 'data-testid': 'chat-colors-card' }, 'Chat colors') };
});
vi.mock('../components/ThemeModeSettings', async () => {
  const { createElement: h } = await import('react');
  return { ThemeModeSettings: () => h('div', { 'data-testid': 'theme-mode-card' }, 'Dark mode') };
});
vi.mock('../components/BackgroundWeatherSettings', async () => {
  const { createElement: h } = await import('react');
  return {
    BackgroundWeatherSettings: () =>
      h('div', { 'data-testid': 'background-weather' },
        'Ambient scene · Pause effects while generating · Scene sound · Scene sound volume'),
  };
});
vi.mock('../components/MoodOnCharacterSettings', async () => {
  const { createElement: h } = await import('react');
  return { MoodOnCharacterSettings: () => h('div', { 'data-testid': 'mood-on-character' }, 'Mood on the character · Drama') };
});
vi.mock('../components/SpellCheckSettings', async () => {
  const { createElement: h } = await import('react');
  return { SpellCheckSettings: () => h('div', { 'data-testid': 'spell-check-card' }, 'Spell check language') };
});
vi.mock('../components/AdultThemesCard', async () => {
  const { createElement: h } = await import('react');
  return { AdultThemesCard: () => h('div', { 'data-testid': 'adult-themes-card' }, '18+ themes') };
});
vi.mock('../components/PorchLifeSettings', async () => {
  const { createElement: h } = await import('react');
  return { PorchLifeSettings: () => h('div', { 'data-testid': 'porch-life-card' }, 'Porch Life') };
});
vi.mock('../components/GenerationSettingsFields', async () => {
  const { createElement: h } = await import('react');
  return { GenerationSettingsFields: () => h('div', { 'data-testid': 'generation-fields' }, 'Temperature') };
});
vi.mock('../components/ModelTransportCard', async () => {
  const { createElement: h } = await import('react');
  return { ModelTransportCard: () => h('div', { 'data-testid': 'model-transport-card' }, 'Model transport') };
});
vi.mock('../components/VoiceMediaSettings', async () => {
  const { createElement: h } = await import('react');
  return { VoiceMediaSettings: () => h('div', { 'data-testid': 'voice-media-card' }, 'Voice & Media') };
});
vi.mock('../components/IdleUnloadSettings', async () => {
  const { createElement: h } = await import('react');
  return { IdleUnloadSettings: () => h('div', { 'data-testid': 'idle-unload-card' }, 'Free graphics memory when idle') };
});
vi.mock('../components/KeepRecentChatsSettings', async () => {
  const { createElement: h } = await import('react');
  return { KeepRecentChatsSettings: () => h('div', { 'data-testid': 'keep-recent-card' }, 'Keep recent chats ready') };
});
vi.mock('../components/ModelPicker', () => ({ ModelPicker: () => null }));
vi.mock('../components/WorkerBackendCard', () => ({ WorkerBackendCard: () => null }));
vi.mock('../components/SuperGrokCard', () => ({ SuperGrokCard: () => null }));

import { SettingsPage } from './SettingsPage';

interface ManifestControl {
  section: string;
  group?: string;
  webMarker: string;
}
const manifest = JSON.parse(
  // Vitest runs with web_ui/ as cwd; the manifest lives at the repo root.
  readFileSync('../docs/design/settings-parity-manifest.json', 'utf8'),
) as { sections: string[]; controls: Record<string, ManifestControl> };

const settings = () => ({
  backend: 'kobold',
  backends: ['kobold', 'openRouter'],
  isLocal: true,
  loadedModel: 'No model loaded',
  remoteApiUrl: '',
  remoteModelName: '',
  hasApiKey: false,
  contextSize: 16384,
  reasoningEnabled: false,
  reasoningEffort: 'medium',
  generation: {},
  systemPrompt: 'You are a friend.',
  additionalSystemPrompt: 'Stay in character.',
  additionalPostHistoryInstructions: 'End with a question.',
});

let container: HTMLDivElement;
let root: Root;

async function open() {
  get.mockImplementation((path: string) => {
    if (path === '/api/settings') return Promise.resolve(settings());
    if (path === '/api/legacy-models') {
      return Promise.resolve({ groups: [{ label: 'Piper voices', bytes: 2 ** 20 }], totalBytes: 2 ** 20 });
    }
    return Promise.resolve({});
  });
  await act(async () => {
    root.render(createElement(SettingsPage));
  });
}

const section = (id: string): HTMLElement | null =>
  container.querySelector(`[data-section="${id}"]`);
const textOf = (el: Element | null) => el?.textContent ?? '';
const clickTab = async (id: string) => {
  const el = container.querySelector<HTMLButtonElement>(`button[role="tab"][data-tab="${id}"]`);
  expect(el, `tab "${id}"`).not.toBeNull();
  await act(async () => {
    el!.click();
  });
};

/**
 * Clicks every tab in manifest order and collects what each section rendered
 * (and each of its groups) while it was mounted. The page shows one tab at a
 * time like the desktop, so a section only exists while its tab is active.
 */
async function visitTabs() {
  await open();
  const sections = new Map<string, string>();
  const groups = new Map<string, string>();
  for (const id of manifest.sections) {
    await clickTab(id);
    sections.set(id, textOf(section(id)));
    // Exactly one section mounts: the tab I just opened. (The desktop shows
    // one tab at a time; a second [data-section] here means a leaked panel.)
    const mounted = [...container.querySelectorAll('[data-section]')].map((el) =>
      el.getAttribute('data-section'),
    );
    expect(mounted, `sections mounted on tab "${id}"`).toEqual([id]);
    for (const g of container.querySelectorAll('[data-section] [data-testid$="-group"]')) {
      groups.set(`${id}/${g.getAttribute('data-testid')}`, textOf(g));
    }
  }
  return { sections, groups };
}

beforeEach(() => {
  vi.useFakeTimers();
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('Settings sections mirror the desktop tabs', () => {
  it('renders the seven tabs in the manifest order, one section at a time', async () => {
    await open();
    const tabs = [...container.querySelectorAll('button[role="tab"]')].map((el) =>
      el.getAttribute('data-tab'),
    );
    expect(tabs).toEqual(manifest.sections);
    // The page opens on General; nothing else is mounted until its tab is
    // clicked — the desktop shows one tab at a time, not a scroll of all.
    expect(section('general')).not.toBeNull();
    expect(section('appearance')).toBeNull();
    expect(textOf(section('general'))).not.toBe('');
  });

  it('mounts every control in its pinned section', async () => {
    const { sections, groups } = await visitTabs();
    for (const [key, control] of Object.entries(manifest.controls)) {
      const host = control.group
        ? groups.get(`${control.section}/${control.group}-group`)
        : sections.get(control.section);
      expect(host, `section "${control.section}" for ${key}`).toBeDefined();
      expect(
        (host ?? '').includes(control.webMarker),
        `${key}: "${control.webMarker}" missing from "${control.group ?? control.section}"`,
      ).toBe(true);
    }
  });

  it('keeps the chat-appearance controls inside their group in Appearance', async () => {
    const { groups } = await visitTabs();
    const group = groups.get('appearance/chat-appearance-group');
    expect(group).toBeDefined();
    for (const key of ['readingSize', 'moodOnCharacter', 'bubbleOpacity', 'chatColors']) {
      expect(
        (group ?? '').includes(manifest.controls[key].webMarker),
        `${key} left the chat-appearance group`,
      ).toBe(true);
    }
  });

  it('keeps the bubble-less chat rows in General, as the desktop does', async () => {
    const { sections } = await visitTabs();
    const general = sections.get('general') ?? '';
    expect(general).toContain(manifest.controls.userMessagesOnRight.webMarker);
    expect(general).toContain(manifest.controls.followStreamingReplies.webMarker);
    expect(general).toContain(manifest.controls.spellCheckLanguage.webMarker);
    // Appearance must not repeat them, and while Appearance is the visible
    // tab General is unmounted entirely — the desktop shows one tab at a
    // time, so a control lives on exactly one tab.
    const appearance = sections.get('appearance') ?? '';
    expect(appearance).not.toContain(manifest.controls.userMessagesOnRight.webMarker);
    expect(appearance).toContain(manifest.controls.darkMode.webMarker);
  });

  it('keeps the 18+ themes switch in the General Porch Life group', async () => {
    const { groups } = await visitTabs();
    const group = groups.get('general/porch-life-group');
    expect(group).toBeDefined();
    expect(group).toContain('18+ themes');
    expect(group).toContain('live in the Porch Life section now');
  });

  it('moves the prompt family out of Generation into General, flat', async () => {
    const { sections } = await visitTabs();
    const general = sections.get('general') ?? '';
    expect(general).toContain('Fallback system prompt');
    expect(general).toContain('Additional system instructions');
    expect(general).toContain('Additional post-history instructions');
    expect(sections.get('generation') ?? '').not.toContain('Fallback system prompt');
  });
});
