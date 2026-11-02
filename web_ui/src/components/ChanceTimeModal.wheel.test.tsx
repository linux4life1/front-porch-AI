// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's Chance Time modal spins a wheel before the card: SPIN starts
// it, the wheel lands and settles on the slot the event hashes to (outcome
// first), only then do the kind banner, the event and Accept show; the
// reveal is folded from the event's kind, Wild Card when none came; and
// under reduce motion the wheel jumps so the card shows at once.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { ChanceTimeModal } from './ChanceTimeModal';
import { CHANCE_WHEEL_SLOTS, fnv1a32 } from '../theme/chanceSpin';

let container: HTMLDivElement;
let root: Root;
let reduce = false;
let frames: FrameRequestCallback[] = [];
let now = 0;

function render(props: Partial<Parameters<typeof ChanceTimeModal>[0]> = {}) {
  act(() => {
    root.render(
      createElement(ChanceTimeModal, {
        event: 'Carmen finds a folded twenty in an old coat.',
        revealed: false,
        onReveal: () => {},
        onAccept: () => {},
        ...props,
      }),
    );
  });
}

/** Runs the wheel's animation frames `seconds` forward in 1/60 s steps. */
function advance(seconds: number) {
  const steps = Math.ceil(seconds * 60);
  for (let i = 0; i < steps; i++) {
    const due = frames;
    frames = [];
    now += 1000 / 60;
    act(() => {
      for (const f of due) f(now);
    });
  }
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  reduce = false;
  frames = [];
  now = 0;
  vi.stubGlobal('matchMedia', (q: string) => ({ matches: reduce && q.includes('reduce'), addEventListener() {}, removeEventListener() {} }));
  vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => {
    frames.push(cb);
    return frames.length;
  });
  vi.stubGlobal('cancelAnimationFrame', () => {});
  vi.spyOn(performance, 'now').mockImplementation(() => now);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

const text = () => container.textContent ?? '';
const wheel = () => container.querySelector('[data-testid="chance-wheel"]') as HTMLCanvasElement;

describe('ChanceTimeModal wheel', () => {
  it('shows the wheel at rest with SPIN, and no event yet', () => {
    render();
    expect(wheel()).toBeTruthy();
    expect(wheel().getAttribute('aria-label')).toBe('The Chance Time wheel');
    expect(text()).toContain('SPIN');
    expect(text()).not.toContain('Carmen finds');
    expect(text()).not.toContain('Accept Your Fate');
  });

  it('SPIN asks the session to start, and the slot is the event\'s hash', () => {
    const onReveal = vi.fn();
    render({ onReveal });
    act(() => {
      (Array.from(container.querySelectorAll('button')).find((b) => b.textContent === 'SPIN') as HTMLButtonElement).click();
    });
    expect(onReveal).toHaveBeenCalledTimes(1);
    const event = 'Carmen finds a folded twenty in an old coat.';
    expect(Number(wheel().dataset.slot)).toBe(fnv1a32(event) % CHANCE_WHEEL_SLOTS);
  });

  it('the card waits for the wheel to land and settle, then shows the kind, '
    + 'the event and Accept', () => {
    render({ revealed: true, kind: 'fortune', label: 'Fortune!', emoji: '🎉' });
    expect(wheel().getAttribute('aria-label')).toBe('The Chance Time wheel, spinning');
    expect(wheel().dataset.effect).toBe('fortune');
    expect(text()).toContain('Spinning');
    expect(text()).not.toContain('Accept Your Fate');
    advance(4.3);
    expect(text()).toContain('Settling');
    expect(text()).not.toContain('Accept Your Fate');
    advance(0.6);
    expect(text()).toContain('Fortune!');
    expect(text()).toContain('Carmen finds a folded twenty');
    expect(text()).toContain('Accept Your Fate');
    expect(container.querySelector('[data-testid="chance-kind"]')?.className).toContain('tone-fortune');
  });

  it('folds the kind to its reveal, Wild Card when none came', () => {
    render({ revealed: true, kind: 'slapstick', label: 'Slapstick!', emoji: '🎪' });
    expect(wheel().dataset.effect).toBe('misfortune');
    render({ revealed: true, kind: 'weather' });
    expect(wheel().dataset.effect).toBe('chaos');
    render({ revealed: true });
    expect(wheel().dataset.effect).toBe('wildCard');
    advance(5);
    expect(text()).toContain('Wild Card');
  });

  it('under reduce motion the wheel jumps and the card shows at once', () => {
    reduce = true;
    render({ revealed: true, kind: 'misfortune', label: 'Misfortune', emoji: '💀' });
    expect(text()).toContain('Misfortune');
    expect(text()).toContain('Accept Your Fate');
  });

  it('Accept calls through', () => {
    const onAccept = vi.fn();
    render({ revealed: true, onAccept });
    advance(5);
    act(() => {
      (Array.from(container.querySelectorAll('button')).find((b) => /Accept/.test(b.textContent ?? '')) as HTMLButtonElement).click();
    });
    expect(onAccept).toHaveBeenCalledTimes(1);
  });
});
