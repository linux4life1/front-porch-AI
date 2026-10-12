// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director Mode on the web: the strip steps out and back in through the same
// /director commands as the desktop, auto-chat toggles while directing, the
// UNDO names who left (or says you stepped out), and the cast keeps two
// characters while you direct.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DirectorStrip, ExitUndoBar } from './DirectorStrip';
import { CastBar, type CastMember } from './CastBar';

let container: HTMLDivElement;
let root: Root;

const render = (el: ReturnType<typeof createElement>) => act(() => root.render(el));
const button = (label: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent?.includes(label));

const member = (name: string, isLite = false): CastMember => ({
  id: name,
  dbId: null,
  name,
  isHost: false,
  isLite,
  realismEnabled: true,
  emotion: null,
  isNext: false,
  hasAvatar: false,
  avatarUrl: '',
});

describe('Director Mode on the web', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.useRealTimers();
  });

  it('steps out, then offers auto-chat and stepping back in', () => {
    const onCommand = vi.fn();
    const onAutoPlay = vi.fn();
    const strip = (directing: boolean, autoPlay = false) =>
      createElement(DirectorStrip, {
        director: { directing, autoPlay },
        busy: false,
        onCommand,
        onAutoPlay,
        onDelay: () => {},
      });

    render(strip(false));
    expect(container.textContent).toContain('You’re in the scene');
    expect(button('Auto-chat')).toBeUndefined();
    act(() => button('Step out to direct')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('/director');

    render(strip(true));
    expect(container.textContent).toContain('You’re directing');
    act(() => button('Auto-chat')!.click());
    expect(onAutoPlay).toHaveBeenLastCalledWith(true);
    render(strip(true, true));
    act(() => button('Pause auto-chat')!.click());
    expect(onAutoPlay).toHaveBeenLastCalledWith(false);
    act(() => button('Step back in')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('/director off');
  });

  it('offers UNDO for a few seconds, worded for who left', () => {
    const onUndo = vi.fn();
    render(createElement(ExitUndoBar, { undo: { name: 'Sam', isUser: true }, onUndo }));
    expect(container.textContent).toContain('You stepped out to direct');
    act(() => button('Undo')!.click());
    expect(onUndo).toHaveBeenCalledOnce();
    expect(container.textContent).toBe('');

    render(createElement(ExitUndoBar, { undo: { name: 'Bram', isUser: false }, onUndo }));
    expect(container.textContent).toContain('Bram left the scene');
    act(() => vi.advanceTimersByTime(8000));
    expect(container.textContent).toBe('');
  });

  it('offers UNDO again for the next exit by the same name', () => {
    const onUndo = vi.fn();
    const bar = (undo: { name: string; isUser: boolean } | null) =>
      createElement(ExitUndoBar, { undo, onUndo });
    render(bar({ name: 'Sam', isUser: true }));
    act(() => button('Undo')!.click());
    render(bar(null)); // the server closed it
    render(bar({ name: 'Sam', isUser: true })); // stepped out again
    expect(container.textContent).toContain('You stepped out to direct');

    act(() => vi.advanceTimersByTime(8000));
    render(bar(null));
    render(bar({ name: 'Sam', isUser: true }));
    expect(container.textContent).toContain('You stepped out to direct');
  });

  it('sets the auto-chat delay while directing, saved when let go', () => {
    const onDelay = vi.fn();
    const strip = (directing: boolean) =>
      createElement(DirectorStrip, {
        director: { directing, autoPlay: false, delaySeconds: directing ? 15 : null },
        busy: false,
        onCommand: () => {},
        onAutoPlay: () => {},
        onDelay,
      });
    render(strip(false));
    expect(container.querySelector('input[type="range"]')).toBeNull();
    render(strip(true));
    const slider = container.querySelector<HTMLInputElement>('input[type="range"]')!;
    expect(container.textContent).toContain('15.0s');
    act(() => {
      const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      set.call(slider, '4.5');
      slider.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(container.textContent).toContain('4.5s');
    expect(onDelay).not.toHaveBeenCalled();
    act(() => {
      slider.dispatchEvent(new Event('pointerup', { bubbles: true }));
    });
    expect(onDelay).toHaveBeenCalledWith(4.5);
  });

  it('keeps two characters while directing, guests included', () => {
    const onCommand = vi.fn();
    render(
      createElement(CastBar, {
        cast: [member('Ayla'), member('Bram'), member('Nell', true)],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand,
        canRemoveMember: false,
      }),
    );
    const removes = [...container.querySelectorAll<HTMLButtonElement>('button[title]')].filter(
      (b) => b.textContent?.trim() === '✕',
    );
    expect(removes.map((b) => b.disabled)).toEqual([true, true, true]);
    expect(removes[0].title).toContain('at least two characters');
  });
});
