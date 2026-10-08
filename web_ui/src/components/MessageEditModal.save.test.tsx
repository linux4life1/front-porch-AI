// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When Save fails the editor must stay put with the user's draft and say why.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, StrictMode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MessageEditModal } from './MessageEditModal';

let container: HTMLDivElement;
let root: Root;

function typeInto(el: HTMLTextAreaElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

function saveButton(): HTMLButtonElement {
  return [...container.querySelectorAll('button')].find((b) =>
    /^Sav/.test(b.textContent ?? ''),
  ) as HTMLButtonElement;
}

function cancelButton(): HTMLButtonElement {
  return [...container.querySelectorAll('button')].find((b) => b.textContent === 'Cancel') as HTMLButtonElement;
}

/** jsdom traverses history on two nested timers, so give the popstate time to land. */
async function flushHistory() {
  for (let i = 0; i < 4; i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
  }
}

function renderEditor(props: { onCancel?: () => void; onSave?: (text: string) => Promise<void>; strict?: boolean }) {
  const onCancel = props.onCancel ?? (() => {});
  const onSave = props.onSave ?? (async () => {});
  const node = createElement(MessageEditModal, { initialText: 'before', onCancel, onSave });
  return act(async () => {
    root.render(props.strict ? createElement(StrictMode, null, node) : node);
  });
}

describe('MessageEditModal save', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    await flushHistory();
    container.remove();
    vi.restoreAllMocks();
  });

  it('keeps the draft and shows the reason when saving fails', async () => {
    const onSave = vi.fn(async () => {
      throw new Error("Couldn't save your edit. Front Porch AI didn't answer.");
    });
    await act(async () => {
      root.render(createElement(MessageEditModal, { initialText: 'before', onCancel: () => {}, onSave }));
    });
    const body = container.querySelector('textarea.msg-edit-body') as HTMLTextAreaElement;
    await act(async () => typeInto(body, 'after'));

    await act(async () => saveButton().click());

    expect(onSave).toHaveBeenCalledWith('after');
    expect(container.querySelector('[role="alert"]')?.textContent).toContain(
      "Couldn't save your edit.",
    );
    expect((container.querySelector('textarea.msg-edit-body') as HTMLTextAreaElement).value).toBe('after');
    expect(saveButton().disabled).toBe(false);
  });
});

describe('MessageEditModal dismiss', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    await flushHistory();
    container.remove();
    vi.restoreAllMocks();
  });

  it('closes on popstate', async () => {
    const onCancel = vi.fn();
    await renderEditor({ onCancel });
    expect(window.history.state.fpMessageEdit).toBe('open');

    await act(async () => {
      window.history.back();
    });
    await flushHistory();

    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('closes on Escape', async () => {
    const onCancel = vi.fn();
    await renderEditor({ onCancel });

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    });
    await flushHistory();

    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('pops the history marker when Cancel closes it', async () => {
    const onCancel = vi.fn();
    const href = window.location.href;
    const back = vi.spyOn(window.history, 'back');
    await renderEditor({ onCancel });
    expect(window.history.state.fpMessageEdit).toBe('open');
    expect(window.location.href).toBe(href);

    await act(async () => {
      cancelButton().click();
    });
    await flushHistory();

    // history.back() moves the index; it does not shrink history.length.
    expect(back).toHaveBeenCalledTimes(1);
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(window.history.state?.fpMessageEdit).not.toBe('open');
    expect(window.location.href).toBe(href);
  });

  it('re-pushes the marker when a dirty back gesture is declined', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    const onCancel = vi.fn();
    await renderEditor({ onCancel });
    const body = container.querySelector('textarea.msg-edit-body') as HTMLTextAreaElement;
    await act(async () => typeInto(body, 'after'));

    await act(async () => {
      window.history.back();
    });
    await flushHistory();

    expect(onCancel).not.toHaveBeenCalled();
    expect(window.history.state.fpMessageEdit).toBe('open');
  });

  it('pushes a single marker under StrictMode', async () => {
    const push = vi.spyOn(window.history, 'pushState');
    await renderEditor({ strict: true });
    await flushHistory();
    const markers = push.mock.calls.filter((args) => args[0]?.fpMessageEdit === 'open');
    expect(markers).toHaveLength(1);
    expect(window.history.state.fpMessageEdit).toBe('open');
  });

  it('pins the sheet to the visual viewport', async () => {
    const listeners: Record<string, () => void> = {};
    const vv = {
      height: 420,
      width: 390,
      offsetTop: 52,
      offsetLeft: 0,
      addEventListener: (type: string, fn: () => void) => {
        listeners[type] = fn;
      },
      removeEventListener: () => {},
    };
    const prev = Object.getOwnPropertyDescriptor(window, 'visualViewport');
    Object.defineProperty(window, 'visualViewport', { configurable: true, value: vv });
    try {
      await renderEditor({});
      const overlay = container.querySelector('.msg-edit-overlay') as HTMLElement;
      expect(overlay.style.getPropertyValue('--fp-vvh')).toBe('420px');
      expect(overlay.style.getPropertyValue('--fp-vv-top')).toBe('52px');
      vv.offsetTop = 80;
      vv.height = 300;
      listeners.scroll();
      expect(overlay.style.getPropertyValue('--fp-vvh')).toBe('300px');
      expect(overlay.style.getPropertyValue('--fp-vv-top')).toBe('80px');
    } finally {
      if (prev) Object.defineProperty(window, 'visualViewport', prev);
      else Reflect.deleteProperty(window, 'visualViewport');
    }
  });
});
