// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The KoboldCpp preset picker when chat uses a preset that is not in the
// engine folder (picked with Browse on the desktop; the phone itself only
// takes presets from the folder). The picker used to have no option for it
// and showed "The app's own settings (automatic)" beside a card saying
// "Uses your preset".

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { KoboldStatusCard, type LocalModel } from './KoboldStatusCard';

const IN_FOLDER = { path: '/k/Long chats.kcpps', name: 'Long chats', line: '32k chat · fitted to the card · smart cache off' };

const USING: LocalModel = {
  model: '/m/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
  modelName: 'Llama 3.2 3B',
  running: false,
  phase: 'stopped',
  preset: {
    path: '/elsewhere/Mine.kcpps',
    name: 'Mine',
    line: '16k chat · set by hand',
    words: 'Loads Llama 3.2 3B with the settings in the file.',
  },
  auto: null,
  presets: [IN_FOLDER],
};

let container: HTMLDivElement;
let root: Root;

async function show(card: LocalModel) {
  get.mockResolvedValue(card);
  await act(async () => {
    root.render(createElement(KoboldStatusCard, { onError: () => {} }));
  });
}

const select = () => container.querySelector<HTMLSelectElement>('#kc-preset')!;
const options = () => Array.from(select().options).map((o) => o.textContent);

beforeEach(() => {
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
});

describe('the preset picker for a preset outside the engine folder', () => {
  it('shows the preset in use, not "automatic"', async () => {
    await show(USING);
    expect(select().value).toBe('/elsewhere/Mine.kcpps');
    expect(options()).toContain('Mine — 16k chat · set by hand');
    expect(container.textContent).toContain('Uses your preset “Mine”.');
  });

  it('a preset in the folder is not listed twice', async () => {
    await show({ ...USING, preset: { ...USING.preset!, path: IN_FOLDER.path, name: IN_FOLDER.name } });
    expect(select().value).toBe(IN_FOLDER.path);
    expect(options()).toHaveLength(2);
  });

  it('no preset in use is "automatic", with only the folder to pick from', async () => {
    await show({ ...USING, preset: null });
    expect(select().value).toBe('');
    expect(options()).toHaveLength(2);
  });
});
