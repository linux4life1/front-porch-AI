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

  it('cues a speaker, sends a beat, pins a goal, clears a whisper and sets the run', () => {
    const onCommand = vi.fn();
    const onGoal = vi.fn();
    const onClearWhisper = vi.fn();
    const onTurnBudget = vi.fn();
    const strip = (goal: string) =>
      createElement(DirectorStrip, {
        director: {
          directing: true,
          autoPlay: true,
          beats: [{ label: 'Time skip', note: 'Time skip: jump ahead.' }],
          goal,
          whispers: [{ id: 'm1', name: 'Ayla', text: 'You are lying.' }],
          turnBudget: 6,
          turnsLeft: 4,
        },
        busy: false,
        onCommand,
        onAutoPlay: () => {},
        onDelay: () => {},
        memberNames: ['Ayla', 'Bram'],
        onGoal,
        onClearWhisper,
        onTurnBudget,
      });

    render(strip(''));
    act(() => button('Bram')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('/speak Bram');
    act(() => button('Time skip')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('Time skip: jump ahead.');

    const input = container.querySelector<HTMLInputElement>('input[aria-label="Scene goal"]')!;
    const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    act(() => {
      setValue.call(input, 'They make up');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    act(() => button('Pin')!.click());
    expect(onGoal).toHaveBeenLastCalledWith('They make up');

    render(strip('They make up'));
    expect(container.textContent).toContain('📌 They make up');
    act(() => container.querySelector<HTMLButtonElement>('[aria-label="Clear the scene goal"]')!.click());
    expect(onGoal).toHaveBeenLastCalledWith('');
    expect(container.textContent).toContain('🤫 Ayla: You are lying.');
    act(() => container.querySelector<HTMLButtonElement>('[aria-label="Clear the whisper to Ayla"]')!.click());
    expect(onClearWhisper).toHaveBeenLastCalledWith('m1');

    expect(container.textContent).toContain('4 left');
    const select = container.querySelector<HTMLSelectElement>('select[aria-label="Auto-chat run length"]')!;
    expect(select.value).toBe('6');
    act(() => {
      select.value = '10';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(onTurnBudget).toHaveBeenLastCalledWith(10);
  });

  it('does not offer the same UNDO again after a reload', () => {
    sessionStorage.clear();
    const undo = { name: 'Sam', isUser: true };
    render(createElement(ExitUndoBar, { undo, onUndo: () => {} }));
    expect(container.textContent).toContain('You stepped out to direct');
    act(() => vi.advanceTimersByTime(9000));
    expect(container.textContent).not.toContain('You stepped out to direct');

    // A reload mounts the bar afresh while the app still has the UNDO open.
    act(() => root.unmount());
    root = createRoot(container);
    render(createElement(ExitUndoBar, { undo, onUndo: () => {} }));
    expect(container.textContent).not.toContain('You stepped out to direct');
    sessionStorage.clear();
  });
});
