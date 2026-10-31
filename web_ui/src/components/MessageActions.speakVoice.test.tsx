// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Speak sends the message's index so the host picks the voice of whoever said
// that line (in a group, the member stamped on the message, not the first one
// with that name). Sending the text alone read every line in the global voice.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api } from '../api/client';
import { MessageActions } from './MessageActions';
import { type Message } from './chatTypes';

let container: HTMLDivElement;
let root: Root;

const line: Message = {
  index: 3,
  text: 'The tide is loud tonight.',
  sender: 'Alex',
  isUser: false,
};

describe('Speak names the line it speaks', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.restoreAllMocks();
  });

  it('posts the message index with the text', async () => {
    const post = vi.spyOn(api, 'postForBlob').mockRejectedValue(new Error('no audio here'));
    act(() => {
      root.render(
        createElement(MessageActions, {
          m: line,
          isLast: false,
          busy: false,
          canSpeak: true,
          onSwipe: vi.fn(),
          onRegenerate: vi.fn(),
          onContinue: vi.fn(),
          onFork: vi.fn(),
          onEdit: vi.fn(),
          onDelete: vi.fn(),
        }),
      );
    });
    const speak = container.querySelector('button[title="Speak"]') as HTMLButtonElement;
    await act(async () => {
      speak.click();
    });
    expect(post).toHaveBeenCalledWith('/api/tts/speak', {
      text: 'The tide is loud tonight.',
      messageIndex: 3,
    });
  });

  it('offers no Speak on a System banner, as on desktop', () => {
    act(() => {
      root.render(
        createElement(MessageActions, {
          m: { ...line, sender: 'System' },
          isLast: false,
          busy: false,
          canSpeak: true,
          onSwipe: vi.fn(),
          onRegenerate: vi.fn(),
          onContinue: vi.fn(),
          onFork: vi.fn(),
          onEdit: vi.fn(),
          onDelete: vi.fn(),
        }),
      );
    });
    expect(container.querySelector('button[title="Speak"]')).toBeNull();
  });
});
