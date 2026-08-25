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

function lastOf<T>(items: T[]): T | undefined {
  return items[items.length - 1];
}

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
  if (!toggle) {
    throw new Error('Custom opening state toggle not found');
  }
  if (toggle.checked === on) return;
  // React 18 wires checkbox onChange to the click path. Setting checked +
  // dispatching a synthetic change does not emit (lastOf was undefined).
  act(() => {
    toggle.click();
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
    expect(lastOf(emitted)).toBeNull();
    expect(container.querySelector('input[type="date"]')).toBeNull();

    clickToggle(true);
    const restored = lastOf(emitted);
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

  it('bond/trust/needs sliders authored then inherit persist undefined, not 0', () => {
    const emitted: Array<GreetingSeed | null> = [];
    render({}, (next) => {
      emitted.push(next);
    });

    function sliderRow(label: string): HTMLElement {
      const rows = Array.from(container.querySelectorAll('.realism-slider')) as HTMLElement[];
      const row = rows.find((el) => {
        const first = el.querySelector('.realism-slider-head > span');
        return first?.textContent === label;
      });
      expect(row, `slider row ${label}`).toBeTruthy();
      return row!;
    }

    function setRange(label: string, value: number) {
      const range = sliderRow(label).querySelector('input[type="range"]') as HTMLInputElement;
      const desc = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!;
      act(() => {
        desc.set!.call(range, String(value));
        range.dispatchEvent(new Event('change', { bubbles: true }));
      });
    }

    function clickInherit(label: string) {
      const btn = sliderRow(label).querySelector('button.realism-badge.muted') as HTMLButtonElement;
      expect(btn, `inherit button for ${label}`).toBeTruthy();
      expect(btn.textContent).toBe('inherit');
      act(() => {
        btn.click();
      });
    }

    setRange('Short-term bond', 20);
    expect(lastOf(emitted)?.shortTermBond).toBe(20);
    setRange('Trust', 10);
    expect(lastOf(emitted)?.trustLevel).toBe(10);
    setRange('Hunger', 25);
    expect(lastOf(emitted)?.needsBaselineHunger).toBe(25);

    clickInherit('Short-term bond');
    expect(lastOf(emitted)?.shortTermBond).toBeUndefined();
    expect(lastOf(emitted)?.shortTermBond).not.toBe(0);

    clickInherit('Trust');
    expect(lastOf(emitted)?.trustLevel).toBeUndefined();
    expect(lastOf(emitted)?.trustLevel).not.toBe(0);

    clickInherit('Hunger');
    const last = lastOf(emitted)!;
    expect(last.shortTermBond).toBeUndefined();
    expect(last.trustLevel).toBeUndefined();
    expect(last.needsBaselineHunger).toBeUndefined();
    expect(last.shortTermBond).not.toBe(0);
    expect(last.trustLevel).not.toBe(0);
    expect(last.needsBaselineHunger).not.toBe(0);
    expect(last.shortTermBond).not.toBe(20);
    expect(last.trustLevel).not.toBe(10);
    expect(last.needsBaselineHunger).not.toBe(25);
  });
});
