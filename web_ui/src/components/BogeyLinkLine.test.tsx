// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Boons & Bogies phase 7: a bogey's boon link on the shared ring card, the
// web twin of the desktop BogeyLinkLine. The line says what holds the flaw
// back, Link / Change opens the picker, and the pick is the growth action
// `link` with the boon id or null.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { BogeyLinkLine } from './BogeyLinkLine';
import { GrowthRingRow, type GrowthRing } from './GrowthPanel';

function ring(
  id: string,
  content: string,
  kind: 'boon' | 'bogey',
  extra: Partial<GrowthRing> = {},
): GrowthRing {
  return {
    id,
    content,
    category: kind === 'bogey' ? 'bogey' : 'skill',
    tier: 'developing',
    strength: 0.6,
    pinned: false,
    retired: false,
    receipts: [],
    kind,
    bbTier: 'skilled',
    ...extra,
  };
}

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const linkText = () =>
  [...container.querySelectorAll('.bogey-link-text')].map((el) => el.textContent ?? '');
const linkButtons = () =>
  [...container.querySelectorAll('.bogey-link-btn')].map((b) => b.textContent);

async function renderRows(rows: GrowthRing[], boons: GrowthRing[], act$ = vi.fn()) {
  await act(async () => {
    root.render(
      createElement(
        'div',
        null,
        ...rows.map((r) =>
          createElement(GrowthRingRow, { key: r.id, ring: r, isPast: false, act: act$, boons }),
        ),
      ),
    );
  });
}

describe('the boon link on the ring card', () => {
  const boon = ring('b1', 'steady hands under pressure', 'boon', { bbTier: 'master' });

  it('says what holds a linked bogey back, and offers Link on an unlinked one', async () => {
    await renderRows(
      [
        boon,
        ring('g1', 'bad temper when cornered', 'bogey', {
          linkedBoon: { id: 'b1', content: 'steady hands under pressure', tier: 'master' },
        }),
        ring('g2', 'skips sleep to finish the job', 'bogey', { linkedBoon: null }),
      ],
      [boon],
    );
    expect(linkText()).toEqual([
      'Held back by steady hands under pressure (Master)',
      'Not linked to a boon',
    ]);
    expect(linkButtons()).toEqual(['Change', 'Link']);
  });

  it('shows no link line on a boon, nor on a bogey with no boon to pick', async () => {
    await renderRows([boon, ring('g1', 'bad temper when cornered', 'bogey')], []);
    expect(linkText()).toEqual([]);
  });

  it('a past bogey shows no link line', async () => {
    await act(async () => {
      root.render(
        createElement(GrowthRingRow, {
          ring: ring('g1', 'bad temper when cornered', 'bogey', { retired: true }),
          isPast: true,
          boons: [boon],
        }),
      );
    });
    expect(linkText()).toEqual([]);
  });

  it('the picker sends `link` with the boon, or null for No boon; Cancel and '
    + 'the current answer send nothing', async () => {
    const act$ = vi.fn();
    const bogey = ring('g1', 'bad temper when cornered', 'bogey', { linkedBoon: null });
    const boons = [ring('b1', 'steady hands under pressure', 'boon')];
    await act(async () => {
      root.render(createElement(BogeyLinkLine, { ring: bogey, boons, act: act$ }));
    });
    const open = () =>
      act(async () => {
        (container.querySelector('.bogey-link-btn') as HTMLButtonElement).click();
      });
    const option = (label: RegExp) =>
      [...container.querySelectorAll('.bogey-link-option')].find((b) =>
        label.test(b.textContent ?? ''),
      ) as HTMLButtonElement;

    await open();
    expect(container.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe(
      'Which boon holds this back?',
    );
    await act(async () => option(/steady hands/).click());
    expect(act$).toHaveBeenLastCalledWith('link', { ringId: 'g1', boonId: 'b1' });
    expect(container.querySelector('[role="dialog"]')).toBeNull();

    // "No boon" on an already-unlinked bogey is no change: nothing is sent.
    await open();
    await act(async () => option(/No boon/).click());
    expect(act$).toHaveBeenCalledTimes(1);

    await open();
    await act(async () => {
      (
        [...container.querySelectorAll('.modal-actions button')].find(
          (b) => b.textContent === 'Cancel',
        ) as HTMLButtonElement
      ).click();
    });
    expect(act$).toHaveBeenCalledTimes(1);

    const linked = { ...bogey, linkedBoon: { id: 'b1', content: 'steady hands', tier: 'novice' } };
    await act(async () => {
      root.render(createElement(BogeyLinkLine, { ring: linked, boons, act: act$ }));
    });
    await open();
    await act(async () => option(/No boon/).click());
    expect(act$).toHaveBeenLastCalledWith('link', { ringId: 'g1', boonId: null });
  });
});
