// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web GreetingSeedForm: Story begins is date+time, {} looks inherit (mild) /
// sliders unset, toggle off/on stashes, fresh enable persists null not {}.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { GreetingSeedForm } from './GreetingSeedForm';
import type { GreetingSeed } from './realism/realismTypes';

let container: HTMLDivElement;
let root: Root;

function Harness({
  initial,
  onEmit,
}: {
  initial: GreetingSeed | null;
  onEmit?: (next: GreetingSeed | null) => void;
}) {
  const [seed, setSeed] = useState<GreetingSeed | null>(initial);
  return createElement(GreetingSeedForm, {
    seed,
    onChange: (next) => {
      onEmit?.(next);
      setSeed(next);
    },
    showNeeds: true,
  });
}

function render(initial: GreetingSeed | null, onEmit?: (next: GreetingSeed | null) => void) {
  act(() => {
    root.render(createElement(Harness, { initial, onEmit }));
  });
}

function clickToggle(on: boolean) {
  const toggle = container.querySelector('input[type="checkbox"]') as HTMLInputElement;
  const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'checked')!;
  act(() => {
    desc.set!.call(toggle, on);
    toggle.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('GreetingSeedForm Story begins and inherit', () => {
  it('empty overlay {} shows inherit (mild) and unset sliders, not moderate', () => {
    render({});
    expect(container.textContent).toContain('inherit (mild)');
    expect(container.textContent).toContain('inherit (morning)');
    const inheritBadges = container.querySelectorAll('.realism-badge.muted');
    expect(inheritBadges.length).toBeGreaterThan(0);
    for (const badge of inheritBadges) {
      expect(badge.textContent).toBe('inherit');
    }
    const intensity = container.querySelector('select') as HTMLSelectElement;
    expect(intensity.value).toBe('');
  });

  it('Story begins has date and time inputs', () => {
    render({});
    const date = container.querySelector('input[type="date"]') as HTMLInputElement;
    const time = container.querySelector('input[type="time"]') as HTMLInputElement;
    expect(date).toBeTruthy();
    expect(time).toBeTruthy();
    expect(container.textContent).toContain('Story begins');
    expect(container.textContent).toContain('Opens at');
  });

  it('toggle off then on stashes the prior authored seed', () => {
    const emitted: Array<GreetingSeed | null> = [];
    render(
      { characterEmotion: 'furious', storyStartDate: '1887-06-01', storyStartTime: '23:47' },
      (next) => {
        emitted.push(next);
      },
    );

    clickToggle(false);
    expect(emitted.at(-1)).toBeNull();
    expect(container.querySelector('input[type="date"]')).toBeNull();

    clickToggle(true);
    const restored = emitted.at(-1);
    expect(restored).toEqual({
      characterEmotion: 'furious',
      storyStartDate: '1887-06-01',
      storyStartTime: '23:47',
    });
    const date = container.querySelector('input[type="date"]') as HTMLInputElement;
    const time = container.querySelector('input[type="time"]') as HTMLInputElement;
    expect(date.value).toBe('1887-06-01');
    expect(time.value).toBe('23:47');
  });

  it('fresh enable persists null, not empty {}', () => {
    const emitted: Array<GreetingSeed | null> = [];
    render(null, (next) => {
      emitted.push(next);
    });
    expect(container.querySelector('input[type="date"]')).toBeNull();

    clickToggle(true);
    expect(emitted).toHaveLength(1);
    expect(emitted[0]).toBeNull();
    expect(container.querySelector('input[type="date"]')).toBeTruthy();
    expect(container.querySelector('input[type="time"]')).toBeTruthy();
  });
});
