// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Voice & Media → Auto-send transcription, honoured by the web's
// dictation as the desktop describes it: with the switch on, what the mic
// heard is sent instead of placed in the box (into an empty box, as on the
// desktop); with it off, the words land in the box as before.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// The real MicButton records from a microphone; this stand-in hands the
// composer a transcript the way the real one does after the upload.
vi.mock('./VoiceControls', async () => {
  const { createElement: h } = await import('react');
  return {
    MicButton: ({ onText }: { onText: (t: string) => void }) =>
      h('button', { type: 'button', 'data-testid': 'mic', onClick: () => onText('hello porch') }, 'mic'),
  };
});

import { ChatComposer } from './ChatComposer';

let container: HTMLDivElement;
let root: Root;
const onSend = vi.fn();

function typeInto(el: HTMLTextAreaElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

async function mount(props: Record<string, unknown>) {
  await act(async () => {
    root.render(
      createElement(ChatComposer, {
        onSend,
        onStop: () => {},
        isGenerating: false,
        canMic: true,
        ...props,
      }),
    );
  });
}

const box = () => container.querySelector('textarea') as HTMLTextAreaElement;
const speak = async () => {
  await act(async () => {
    (container.querySelector('[data-testid="mic"]') as HTMLButtonElement).click();
  });
};

describe('ChatComposer auto-send transcription', () => {
  beforeEach(() => {
    onSend.mockClear();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.restoreAllMocks();
  });

  it('sends what the mic heard when Auto-send is on, leaving the box empty', async () => {
    await mount({ autoSendMic: true });
    await speak();
    expect(onSend).toHaveBeenCalledWith('hello porch');
    expect(box().value).toBe('');
  });

  it('places it in the box when Auto-send is off', async () => {
    await mount({ autoSendMic: false });
    await speak();
    expect(onSend).not.toHaveBeenCalled();
    expect(box().value).toBe('hello porch');
  });

  it('joins a typed draft instead of sending it, as the desktop does', async () => {
    await mount({ autoSendMic: true });
    await act(async () => typeInto(box(), 'and also'));
    await speak();
    expect(onSend).not.toHaveBeenCalled();
    expect(box().value).toBe('and also hello porch');
  });

  it('never sends while a reply is still coming', async () => {
    await mount({ autoSendMic: true, isGenerating: true });
    await speak();
    expect(onSend).not.toHaveBeenCalled();
    expect(box().value).toBe('hello porch');
  });
});
