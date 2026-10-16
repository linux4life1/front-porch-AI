// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone twin of the desktop bubble's Pockets & Wardrobe receipt chips and
// Director verifier chip (message_bubble.realism_chips.dart). Pockets runs
// with Realism off, so receipts alone must still render the row.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ChipsRow } from './ChipsRow';
import { type Chips } from './chatTypes';

const LONG = 'put on: a heavy waxed-canvas barn coat with a corduroy collar and brass snaps';

let container: HTMLDivElement;
let root: Root;

function render(chips: Chips) {
  act(() =>
    root.render(
      createElement(ChipsRow, { chips, isLast: false, busy: false, onReprocess: () => {}, onRevert: () => {} }),
    ),
  );
}

const chips = () => [...container.querySelectorAll<HTMLElement>('.chips-row.realism .chip')];
const tap = (el: HTMLElement) => act(() => el.dispatchEvent(new MouseEvent('click', { bubbles: true })));

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

describe('ChipsRow Pockets & Wardrobe receipts', () => {
  it('renders one chip per receipt when receipts are the only chips', () => {
    render({ pocketChanges: ['picked up: car keys', LONG] });
    const found = chips();
    expect(found).toHaveLength(2);
    expect(found.every((c) => c.classList.contains('pocket'))).toBe(true);
    expect(found[0].querySelector('.chip-label')?.textContent).toBe('🧥 picked up: car keys');
    expect(found[0].title).toBe('Pockets & Wardrobe: picked up: car keys');
    expect(container.querySelector('.chip.up, .chip.down')).toBeNull();
  });

  it('a tap reveals the whole receipt, however long', () => {
    render({ pocketChanges: [LONG] });
    const [chip] = chips();
    expect(chip.getAttribute('role')).toBe('button');
    tap(chip);
    expect(container.querySelector('.chip-reason')?.textContent).toBe(`Pockets & Wardrobe: ${LONG}`);
  });

  it('skips blank receipts and renders nothing when none are left', () => {
    render({ pocketChanges: ['  ', ''] });
    expect(container.querySelector('.chips-block')).toBeNull();
  });

  it('keeps a long label on one line with an ellipsis inside the bubble', () => {
    const css = readFileSync(join(__dirname, '../styles/insight.css'), 'utf8');
    const rule = (sel: string) => css.match(new RegExp(`\\n${sel.replace('.', '\\.')}\\s*\\{([^}]*)\\}`))?.[1] ?? '';
    expect(rule('.chip')).toMatch(/white-space:\s*nowrap/);
    expect(rule('.chip')).toMatch(/max-width:\s*100%/);
    expect(rule('.chip-label')).toMatch(/text-overflow:\s*ellipsis/);
    expect(rule('.chip-label')).toMatch(/overflow:\s*hidden/);
  });
});

describe('ChipsRow Director verifier', () => {
  it('shows "Director accepted" with the reason on tap', () => {
    render({ directorStatus: 'accepted', directorPasses: 0, directorReason: 'Matches the scene.' });
    const [chip] = chips();
    expect(chip.querySelector('.chip-label')?.textContent).toBe('✓ Director accepted');
    expect(chip.classList.contains('up')).toBe(true);
    tap(chip);
    expect(container.querySelector('.chip-reason')?.textContent).toBe('Matches the scene.');
  });

  it('counts reprocesses on a correction, singular and plural', () => {
    render({ directorStatus: 'corrected', directorPasses: 1 });
    expect(chips()[0].textContent).toContain('🕵️ Director corrected (1 reprocess)');
    expect(chips()[0].title).toBe('Realism Verification result');
    render({ directorStatus: 'corrected', directorPasses: 3 });
    expect(chips()[0].textContent).toContain('🕵️ Director corrected (3 reprocesses)');
  });

  it('sits in the same row as the receipts', () => {
    render({ directorStatus: 'accepted', pocketChanges: ['dropped: umbrella'] });
    expect(chips().map((c) => c.querySelector('.chip-label')?.textContent)).toEqual([
      '✓ Director accepted',
      '🧥 dropped: umbrella',
    ]);
  });
});
