// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-character Pockets switch lives on the Wearing / Carrying card —
// not as an orphan above Optional Features.

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

describe('Pockets panel placement', () => {
  it('puts the per-character switch inside the Wearing / Carrying card', () => {
    render();
    const panel = container.querySelector('[data-testid="character-pockets-panel"]');
    expect(panel).toBeTruthy();
    expect(panel!.textContent).toContain('Pockets & Wardrobe');
    expect(panel!.textContent).toContain('skips inventory tracking');
    expect(panel!.textContent).toContain('Wearing');
    expect(panel!.textContent).toContain('Carrying');
  });

  it('hides Wearing and Carrying editors when the character switch is off', () => {
    render({ pocketsEnabled: false });
    const panel = container.querySelector('[data-testid="character-pockets-panel"]');
    expect(panel).toBeTruthy();
    expect(panel!.textContent).toContain('Pockets & Wardrobe');
    expect(panel!.textContent).not.toContain('flour-dusted apron');
    expect(panel!.textContent).toContain('Turn this on to edit the starting kit');
    expect(panel!.querySelector('.chiplist')).toBeNull();
  });
});
