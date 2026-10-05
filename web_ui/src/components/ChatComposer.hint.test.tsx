// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opening a chat starts the host's KoboldCpp. When that start was refused (the
// model file is not a GGUF, say) the chat state carries why in `llmHint`, and
// the composer says it above the box that reads "No API connection", for as
// long as there is no connection. A connected composer never shows it, and a
// host that does not send the field leaves the composer as it was.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ChatComposer } from './ChatComposer';

const WORDS =
  'Not a valid GGUF model file:\n/m/broken.gguf\nThe file is probably a partial or corrupted download.';

let container: HTMLDivElement;
let root: Root;

function render(apiReady: boolean, apiHint?: string | null) {
  act(() => {
    root.render(
      createElement(ChatComposer, {
        onSend: vi.fn(),
        onStop: vi.fn(),
        isGenerating: false,
        canMic: false,
        apiReady,
        apiHint,
      }),
    );
  });
}

const hint = () => container.querySelector('[data-testid="composer-api-hint"]');

describe('ChatComposer connection hint', () => {
  beforeEach(() => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('says why the start was refused while there is no connection', () => {
    render(false, WORDS);
    expect(hint()!.textContent).toBe(WORDS);
    expect(container.querySelector('textarea')!.placeholder).toBe('No API connection');
  });

  it('says nothing once there is a connection, whatever the host still holds', () => {
    render(false, WORDS);
    render(true, WORDS);
    expect(hint()).toBeNull();
  });

  it('is as it was when the host sends no reason', () => {
    render(false);
    expect(hint()).toBeNull();
    render(false, null);
    expect(hint()).toBeNull();
  });
});
