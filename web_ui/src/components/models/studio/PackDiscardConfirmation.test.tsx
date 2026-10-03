// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act, createElement, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { expect, it, vi } from 'vitest';
import { PackDiscardConfirmation } from './PackDiscardConfirmation';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

it('focuses Keep, closes on Escape, and returns focus to New pack', () => {
  const discard = vi.fn();
  function Panel() {
    const trigger = useRef<HTMLButtonElement>(null);
    const [open, setOpen] = useState(false);
    return createElement('div', null,
      createElement('button', { ref: trigger, onClick: () => setOpen(true) }, 'New pack'),
      open ? createElement(PackDiscardConfirmation, {
        busy: false, trigger, onDiscard: discard, onKeep: () => setOpen(false),
      }) : null,
    );
  }
  const host = document.createElement('div');
  document.body.append(host);
  const root = createRoot(host);
  try {
    act(() => root.render(createElement(Panel)));
    const trigger = host.querySelector('button')!;
    act(() => trigger.click());
    expect(document.activeElement?.textContent).toBe('Keep this pack');
    act(() => document.activeElement!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(host.querySelector('[role="alertdialog"]')).toBeNull();
    expect(document.activeElement).toBe(trigger);
    expect(discard).not.toHaveBeenCalled();
    act(() => trigger.click());
    act(() => (document.activeElement as HTMLButtonElement).click());
    expect(document.activeElement).toBe(trigger);
    expect(discard).not.toHaveBeenCalled();
  } finally {
    act(() => root.unmount());
    host.remove();
  }
});
