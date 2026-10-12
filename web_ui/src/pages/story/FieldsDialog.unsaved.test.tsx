// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The studio's edit dialogs close on Esc or a tap outside. With something
// typed that used to drop it silently; now it asks first. Save never asks.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UNSAVED_QUESTION } from '../../hooks/useUnsavedChanges';
import { FieldsDialog } from './FieldsDialog';

let container: HTMLDivElement;
let root: Root;
const onCancel = vi.fn();
const onSubmit = vi.fn();

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  onCancel.mockReset();
  onSubmit.mockReset();
  act(() =>
    root.render(
      <FieldsDialog title="Rename" fields={[{ key: 'title', hint: 'Title', value: 'Tidewater' }]}
        onSubmit={onSubmit} onCancel={onCancel} />,
    ),
  );
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

const field = () => container.querySelector('input') as HTMLInputElement;

function type(value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(field(), value);
    field().dispatchEvent(new Event('input', { bubbles: true }));
  });
}

const escape = () =>
  act(() => {
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  });
const tapOutside = () =>
  act(() => {
    container.querySelector('.s-backdrop')!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
  });

describe('a story edit dialog with typed input', () => {
  it('closes on Esc without asking when nothing changed', () => {
    const confirm = vi.spyOn(window, 'confirm');
    escape();
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before Esc, a tap outside or Cancel drops typed input', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    type('Tidewater Rising');
    escape();
    tapOutside();
    const cancel = [...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Cancel')!;
    act(() => cancel.click());
    expect(confirm).toHaveBeenCalledTimes(3);
    expect(confirm).toHaveBeenCalledWith(UNSAVED_QUESTION);
    expect(onCancel).not.toHaveBeenCalled();

    confirm.mockReturnValue(true);
    escape();
    expect(onCancel).toHaveBeenCalledTimes(1);
  });

  it('Save does not ask', () => {
    const confirm = vi.spyOn(window, 'confirm');
    type('Tidewater Rising');
    const save = container.querySelector('[data-testid="story-dialog-confirm"]') as HTMLButtonElement;
    act(() => save.click());
    expect(onSubmit).toHaveBeenCalledWith({ title: 'Tidewater Rising' });
    expect(confirm).not.toHaveBeenCalled();
  });

  it('a reload or tab close asks only while something is typed', () => {
    const clean = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(clean);
    expect(clean.defaultPrevented).toBe(false);

    type('Tidewater Rising');
    const dirty = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(dirty);
    expect(dirty.defaultPrevented).toBe(true);
  });
});
