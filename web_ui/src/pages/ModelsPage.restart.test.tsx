// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Restart on the Models page, with KoboldCpp stopped. When the host could not
// start it (the model file is not a GGUF, say) the answer carries why in
// `refused`, and it is said beside the buttons: the page used to go on saying
// "Stopped" and nothing more. The real page runs; the answer is the one the
// host's restart route gives (refused_start_phone_test.dart pins it on the
// Dart side).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The rest of the page has its own tests; here it is only in the way.
vi.mock('../components/models/HardwarePanel', () => ({ HardwarePanel: () => null }));
vi.mock('../components/models/LocalModels', () => ({ LocalModels: () => null }));
vi.mock('../components/models/ModelDownloads', () => ({ ModelDownloads: () => null }));
vi.mock('../components/models/ImageGen', () => ({ ImageGen: () => null }));
vi.mock('../components/models/KoboldStatusCard', () => ({ KoboldStatusCard: () => null }));

import { ModelsPage } from './ModelsPage';

const WORDS =
  'Not a valid GGUF model file:\n/m/broken.gguf\nThe file is probably a partial or corrupted download.';

const status = (refused?: string | null) => ({
  isLocal: true,
  running: false,
  starting: false,
  phase: 'stopped',
  statusMessage: '',
  loadedModel: 'broken.gguf',
  engineInstalled: true,
  ...(refused === undefined ? {} : { refused }),
});

let container: HTMLDivElement;
let root: Root;

async function show() {
  get.mockResolvedValue(status());
  await act(async () => {
    root.render(createElement(ModelsPage));
  });
}

const click = async (label: string) => {
  await act(async () => {
    Array.from(container.querySelectorAll('button'))
      .find((b) => b.textContent === label)!
      .click();
  });
};

const shown = () => container.querySelector('[data-testid="backend-refused"]');

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

describe('Restart with KoboldCpp stopped', () => {
  it('says why it did not start, beside the buttons', async () => {
    await show();
    post.mockResolvedValue(status(WORDS));

    await click('Restart');

    expect(post).toHaveBeenCalledWith('/api/backend/restart');
    expect(shown()!.textContent).toBe(WORDS);
  });

  it('says nothing when it started, or the host does not send the field', async () => {
    await show();
    post.mockResolvedValue(status(null));
    await click('Restart');
    expect(shown()).toBeNull();

    // An older app answers with the status alone.
    post.mockResolvedValue(status());
    await click('Restart');
    expect(shown()).toBeNull();
  });

  it('forgets the last refusal when the next button is pressed', async () => {
    await show();
    post.mockResolvedValue(status(WORDS));
    await click('Restart');
    expect(shown()).not.toBeNull();

    post.mockResolvedValue(status(null));
    await click('Restart');
    expect(shown()).toBeNull();
  });
});
