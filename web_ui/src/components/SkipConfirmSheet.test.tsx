// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Did time pass?" on the web (#629): the server's offers with the guess
// picked, "No skip" and "Other…", the button naming where the clock lands,
// nothing preselected when the reader failed, and closing keeps the guess.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SkipConfirmSheet, type PendingSkip, type SkipAnswer } from './SkipConfirmSheet';

const pending: PendingSkip = {
  line: '*We fell asleep and slept eight hours before we woke up.*',
  reason: 'disagrees',
  question: "Your message could be read more than one way. It's 1:40 AM now.",
  now: '1:40 AM',
  choices: [
    { label: 'Next morning · 8:00 AM', minutes: 0, until: 'morning', slept: true },
    { label: '8 hours · 9:40 AM', minutes: 480, until: '', slept: true },
  ],
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  root.unmount();
  container.remove();
});

function render(p: PendingSkip, onAnswer: (a: SkipAnswer) => void) {
  act(() => root.render(createElement(SkipConfirmSheet, { pending: p, onAnswer })));
}

const button = (name: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === name);
const primary = () => container.querySelector('button.primary') as HTMLButtonElement;

describe('SkipConfirmSheet', () => {
  it('offers the server\'s skips with the guess picked, then No skip and Other…', () => {
    render(pending, () => {});
    expect(container.textContent).toContain("It's 1:40 AM now.");
    expect(button('Next morning · 8:00 AM')?.getAttribute('aria-pressed')).toBe('true');
    expect(button('8 hours · 9:40 AM')).toBeTruthy();
    expect(button('No skip')).toBeTruthy();
    expect(button('Other…')).toBeTruthy();
    expect(primary().textContent).toBe('Skip to 8:00 AM');
  });

  it('answers the picked offer, no skip, or typed text', () => {
    const onAnswer = vi.fn();
    render(pending, onAnswer);
    act(() => void button('8 hours · 9:40 AM')!.click());
    expect(primary().textContent).toBe('Skip to 9:40 AM');
    act(() => void primary().click());
    expect(onAnswer).toHaveBeenLastCalledWith({ choice: 1 });

    act(() => void button('No skip')!.click());
    act(() => void primary().click());
    expect(onAnswer).toHaveBeenLastCalledWith({ none: true });

    act(() => void button('Other…')!.click());
    expect(primary().disabled).toBe(true);
    const input = container.querySelector('input.skip-other') as HTMLInputElement;
    act(() => {
      const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      set.call(input, '3h');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    act(() => void primary().click());
    expect(onAnswer).toHaveBeenLastCalledWith({ other: '3h' });
  });

  it('a failed reading picks nothing; closing keeps the guess', () => {
    const onAnswer = vi.fn();
    render({ ...pending, reason: 'noReading' }, onAnswer);
    expect(primary().disabled).toBe(true);
    expect(primary().textContent).toBe('Pick one');
    act(() => void button('Close')!.click());
    expect(onAnswer).toHaveBeenLastCalledWith({});
  });
});
