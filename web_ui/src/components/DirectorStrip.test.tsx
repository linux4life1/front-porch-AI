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
const chipEl = (name: string) =>
  [...container.querySelectorAll<HTMLElement>('.cast-chip')].find((c) => c.textContent?.includes(name))!;
const openMenu = (name: string) =>
  act(() =>
    chipEl(name).dispatchEvent(
      new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 10, clientY: 10 }),
    ),
  );

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

  it('pauses auto-chat with its turns kept, resumes it, and stops the run', () => {
    const onAutoPlay = vi.fn();
    const onPauseAutoPlay = vi.fn();
    const strip = (autoPlay: boolean, autoPlayPaused = false) =>
      createElement(DirectorStrip, {
        director: { directing: true, autoPlay, autoPlayPaused, turnsLeft: 2 },
        busy: false,
        onCommand: () => {},
        onAutoPlay,
        onPauseAutoPlay,
        onDelay: () => {},
      });

    render(strip(true));
    act(() => button('Pause auto-chat')!.click());
    expect(onPauseAutoPlay).toHaveBeenCalledOnce();
    expect(onAutoPlay).not.toHaveBeenCalled();

    render(strip(false, true));
    act(() => button('Resume auto-chat (2 left)')!.click());
    expect(onAutoPlay).toHaveBeenLastCalledWith(true);
    act(() => button('Stop auto-chat')!.click());
    expect(onAutoPlay).toHaveBeenLastCalledWith(false);

    render(strip(false));
    expect(button('Stop auto-chat')).toBeUndefined();
    expect(button('Resume')).toBeUndefined();
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

  // The strip is the desktop's (cast_roster_chip.dart): faces, names, honest
  // status words, the Next pill and Promote. The GUEST label is gone — the
  // wider chip with a Promote button is the guest's own sign. Removing a
  // member is Edit group's Cast; the old web-only ✕ left with it.
  it('draws the desktop faces: no remove, speak or add control on the strip', () => {
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
        onCommand: () => {},
        onQueue: () => {},
        canRemoveMember: false,
      }),
    );
    const labels = [...container.querySelectorAll('button')].map((b) => b.textContent?.trim());
    expect(labels).not.toContain('✕');
    expect(labels).not.toContain('🗣');
    expect(labels).not.toContain('＋');
    expect(labels).not.toContain('Scan scene');
    expect(container.querySelectorAll('.cast-face').length).toBe(3);
    expect(container.textContent).not.toContain('GUEST');
    expect(labels.filter((l) => l?.includes('⏭ Next'))).toHaveLength(3);
    expect(labels).toContain('Promote');
  });

  it('wears honest status words; the menu sends away and brings back; at work offers neither', () => {
    const onSetAway = vi.fn();
    render(
      createElement(CastBar, {
        cast: [
          { ...member('Ayla'), presence: 'withYou' },
          { ...member('Bram'), presence: 'away' },
          { ...member('Cleo'), presence: 'atWork' },
        ],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand: () => {},
        onSetAway,
      }),
    );
    // The word row describes; it no longer acts.
    const words = [...container.querySelectorAll('.cast-word')].map((w) => w.textContent);
    expect(words).toEqual(['With you', 'Away', 'At work']);

    openMenu('Ayla');
    act(() => button('Send away')!.click());
    expect(onSetAway).toHaveBeenLastCalledWith('Ayla', true);
    openMenu('Bram');
    act(() => button('Bring back')!.click());
    expect(onSetAway).toHaveBeenLastCalledWith('Bram', false);
    expect(onSetAway).toHaveBeenCalledTimes(2);

    // At work belongs to the clock's shift: no toggle in the menu.
    openMenu('Cleo');
    expect(button('Send away')).toBeUndefined();
    expect(button('Bring back')).toBeUndefined();

    const chips = [...container.querySelectorAll('.cast-chip')];
    expect(chips.map((c) => c.classList.contains('away'))).toEqual([false, true, true]);
  });

  it('a lite group member wears the status word and is sent away and brought back like a full one', () => {
    const onSetAway = vi.fn();
    const draw = (presence: 'withYou' | 'away') =>
      render(
        createElement(CastBar, {
          cast: [{ ...member('Misty', true), presence }],
          focusedId: null,
          busy: false,
          guestStatus: null,
          guestIsError: false,
          pendingDetection: null,
          onFocus: () => {},
          onAdd: () => {},
          onCommand: () => {},
          onSetAway,
        }),
      );
    draw('withYou');
    expect(container.querySelector('.cast-word')?.textContent).toBe('With you');
    openMenu('Misty');
    expect(button('Promote to full member')).toBeDefined();
    act(() => button('Send away')!.click());
    expect(onSetAway).toHaveBeenLastCalledWith('Misty', true);

    draw('away');
    expect(container.querySelector('.cast-word')?.textContent).toBe('Away');
    expect(chipEl('Misty').classList.contains('away')).toBe(true);
    openMenu('Misty');
    act(() => button('Bring back')!.click());
    expect(onSetAway).toHaveBeenLastCalledWith('Misty', false);
  });

  it('keeps the Next pill live while the turn settles (a hold fires nothing) but disables the menu away row', () => {
    render(
      createElement(CastBar, {
        cast: [{ ...member('Ayla'), presence: 'withYou' }],
        focusedId: null,
        busy: false,
        settling: true,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand: () => {},
        onSetAway: () => {},
        onQueue: () => {},
      }),
    );
    expect(button('⏭ Next')!.disabled).toBe(false);
    openMenu('Ayla');
    expect(button('Send away')!.disabled).toBe(true);
  });

  it('opens the chip menu on a phone long-press, without firing focus', () => {
    const onFocus = vi.fn();
    render(
      createElement(CastBar, {
        cast: [{ ...member('Ayla'), presence: 'withYou' }],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus,
        onAdd: () => {},
        onCommand: () => {},
        onSetAway: () => {},
        onQueue: () => {},
      }),
    );
    const down = new MouseEvent('pointerdown', {
      bubbles: true,
      cancelable: true,
      clientX: 40,
      clientY: 40,
    });
    Object.defineProperty(down, 'pointerType', { value: 'touch' });
    act(() => chipEl('Ayla').dispatchEvent(down));
    expect(container.querySelector('.cast-menu')).toBeNull();
    act(() => {
      vi.advanceTimersByTime(500);
    });
    expect(container.querySelector('.cast-menu')).not.toBeNull();
    // The release-click after a hold must not also focus the member.
    act(() => button('Ayla')!.click());
    expect(onFocus).not.toHaveBeenCalled();
  });

  it('a hold with a clickless release does not dead-tap the next chip', () => {
    // iOS long-press on the avatar eats the release click; the next real
    // touch (another chip) must arrive live, not get swallowed by a
    // stale suppression flag.
    const onFocus = vi.fn();
    render(
      createElement(CastBar, {
        cast: [member('Ayla'), member('Bram')],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus,
        onAdd: () => {},
        onCommand: () => {},
        onQueue: () => {},
      }),
    );
    const touchDown = (el: Element) => {
      const down = new MouseEvent('pointerdown', {
        bubbles: true,
        cancelable: true,
        clientX: 40,
        clientY: 40,
      });
      Object.defineProperty(down, 'pointerType', { value: 'touch' });
      act(() => el.dispatchEvent(down));
    };
    touchDown(chipEl('Ayla'));
    act(() => {
      vi.advanceTimersByTime(500);
    });
    expect(container.querySelector('.cast-menu')).not.toBeNull();

    touchDown(chipEl('Bram')); // the next touch resets the flag
    act(() => button('Bram')!.click());
    expect(onFocus).toHaveBeenLastCalledWith('Bram');
  });

  it('draws no Next pill when the app passes no queue wiring', () => {
    render(
      createElement(CastBar, {
        cast: [member('Ayla')],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand: () => {},
      }),
    );
    expect(container.querySelector('.cast-next')).toBeNull();
  });

  it('queues from the pill and cancels a hold from the filled NEXT', () => {
    const onQueue = vi.fn();
    render(
      createElement(CastBar, {
        cast: [member('Ayla')],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand: () => {},
        onQueue,
      }),
    );
    act(() => button('⏭ Next')!.click());
    expect(onQueue).toHaveBeenLastCalledWith('Ayla', true);

    render(
      createElement(CastBar, {
        cast: [{ ...member('Ayla'), queued: true }],
        focusedId: null,
        busy: false,
        guestStatus: null,
        guestIsError: false,
        pendingDetection: null,
        onFocus: () => {},
        onAdd: () => {},
        onCommand: () => {},
        onQueue,
      }),
    );
    expect(chipEl('Ayla').classList.contains('queued')).toBe(true);
    act(() => button('✓ NEXT')!.click());
    expect(onQueue).toHaveBeenLastCalledWith('Ayla', false);
  });

  it('cues a speaker, sends a beat, pins a goal, clears a whisper and sets the run', () => {
    const onCommand = vi.fn();
    const onCueQueue = vi.fn();
    const onGoal = vi.fn();
    const onClearWhisper = vi.fn();
    const onTurnBudget = vi.fn();
    const strip = (goal: string, cue: boolean = true) =>
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
        queuedName: null,
        onCueQueue: cue ? onCueQueue : undefined,
        onGoal,
        onClearWhisper,
        onTurnBudget,
      });

    render(strip(''));
    act(() => button('Bram')!.click());
    expect(onCueQueue).toHaveBeenLastCalledWith('Bram', true);
    expect(onCommand).not.toHaveBeenCalled();
    act(() => button('Time skip')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('Time skip: jump ahead.');

    // No queue wiring (older server): the old command text still fires.
    render(strip('', false));
    act(() => button('Bram')!.click());
    expect(onCommand).toHaveBeenLastCalledWith('/speak Bram');

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
