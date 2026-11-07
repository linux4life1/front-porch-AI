// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Work identity chrome on create/edit — occupation title, What the job is
// (occupationBrief), Start/End. Same surface as desktop WorkRow, not a stub.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { RealismFormSection } from './RealismFormSection';
import { REALISM_DEFAULTS, type RealismValues } from './realismTypes';

let container: HTMLDivElement;
let root: Root;

function Harness({ initial }: { initial?: Partial<RealismValues> }) {
  const [v, setV] = useState<RealismValues>({ ...REALISM_DEFAULTS, ...initial });
  return createElement(RealismFormSection, {
    v,
    set: (patch: Partial<RealismValues>) => setV((cur) => ({ ...cur, ...patch })),
  });
}

function render(initial?: Partial<RealismValues>) {
  act(() => {
    root.render(createElement(Harness, { initial }));
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

describe('Work identity chrome', () => {
  it('shows occupation, What the job is, and Start/End', () => {
    render();
    expect(container.querySelector('[data-testid="work-occupation"]')).toBeTruthy();
    expect(container.querySelector('[data-testid="work-brief"]')).toBeTruthy();
    expect(container.querySelector('[data-testid="work-start"]')).toBeTruthy();
    expect(container.querySelector('[data-testid="work-end"]')).toBeTruthy();
    expect(container.textContent).toContain('What the job is');
    expect(container.textContent).toContain('Occupation');
    expect(container.textContent).toContain('Start');
    expect(container.textContent).toContain('End');
  });

  it('loads a stored brief and keeps typing it', () => {
    render({
      occupation: 'librarian',
      occupationBrief: 'Keeps the lamp and logs the ships',
      hours: '9am–5pm',
    });
    const brief = container.querySelector('[data-testid="work-brief"]') as HTMLTextAreaElement;
    expect(brief.value).toBe('Keeps the lamp and logs the ships');

    act(() => {
      const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!;
      setter.call(brief, 'shelves returns, then reads until close');
      brief.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(brief.value).toBe('shelves returns, then reads until close');
  });

  it('empty brief stays empty — today stays today', () => {
    render({ occupation: 'librarian' });
    const brief = container.querySelector('[data-testid="work-brief"]') as HTMLTextAreaElement;
    expect(brief.value).toBe('');
  });

  it('shows seven day chips', () => {
    render({ occupation: 'librarian', hours: '9am–5pm' });
    for (let d = 1; d <= 7; d++) {
      expect(container.querySelector(`[data-testid="work-day-${d}"]`)).toBeTruthy();
    }
    expect(container.textContent).toContain('Weekdays unless you tap others');
  });
});

// The card's Afterglow switch: how new chats with this character start Lust
// and recovery. It shows only while Porch Life (with 18+) allows Afterglow,
// and the Recovery block shows while it is on. Red proof: dropping the row
// fails the first case.
describe("RealismFormSection's Afterglow switch", () => {
  it('shows while Porch Life allows it, sets the card, and hides Recovery when off', () => {
    const on: RealismValues = { ...REALISM_DEFAULTS, realismEnabled: true };
    let latest: RealismValues = on;
    function Card() {
      const [v, setV] = useState<RealismValues>(on);
      latest = v;
      return createElement(RealismFormSection, {
        v,
        set: (patch: Partial<RealismValues>) => setV((cur) => ({ ...cur, ...patch })),
        showIntimate: true,
        afterglowOn: true,
      });
    }
    act(() => {
      root.render(createElement(Card));
    });
    const row = [...container.querySelectorAll('label')].find((l) =>
      l.textContent?.startsWith('Afterglow'),
    );
    const box = row?.querySelector<HTMLInputElement>('input[type="checkbox"]');
    expect(box?.checked).toBe(true);
    expect(container.querySelector('[data-testid="recovery-block"]')).toBeTruthy();

    act(() => box?.click());
    expect(latest.afterglowEnabled).toBe(false);
    expect(container.querySelector('[data-testid="recovery-block"]')).toBeNull();
  });

  it('is absent while Porch Life does not allow Afterglow', () => {
    act(() => {
      root.render(
        createElement(RealismFormSection, {
          v: { ...REALISM_DEFAULTS, realismEnabled: true },
          set: () => {},
          showIntimate: true,
          afterglowOn: false,
        }),
      );
    });
    const labels = [...container.querySelectorAll('label')].map((l) => l.textContent ?? '');
    expect(labels.some((t) => t.startsWith('Afterglow'))).toBe(false);
  });
});
