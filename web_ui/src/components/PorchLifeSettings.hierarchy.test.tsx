// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () =>
      Promise.resolve({
        realism: {
          realismAllowed: true,
          journalEnabled: true,
          passageOfTimeDefault: true,
          adultThemesEnabled: false,
        },
      }),
    post: async () => ({}),
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');
const { AdultThemesCard } = await import('./AdultThemesCard');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Porch Life hierarchy, collapsibility, and desktop parity', () => {
  it('starts expanded, toggles per-row details via title/subtitle, omits clutter badges, and uses role=switch', () => {
    expect(container.textContent).toContain(
      'Tracks bond, trust, physical state, and lingering moods across turns.',
    );
    expect(container.textContent).toContain('Slow character evolution');
    expect(container.textContent).toContain('How often');
    expect(container.textContent).not.toContain('Collapse all groups');
    expect(container.textContent).not.toContain('Hide details');
    expect(container.textContent).not.toContain('works alone');
    expect(container.textContent).not.toContain('Extra AI call');
    expect(container.textContent).not.toContain('Per-chat');
    expect(container.textContent).not.toContain('Live global');

    const passageToggle = container.querySelector<HTMLInputElement>(
      'input[aria-label="Passage of Time"]',
    );
    expect(passageToggle?.getAttribute('role')).toBe('switch');
    expect(passageToggle?.className).toContain('switch');

    // Clicking the row title/subtitle button collapses and restores that row's details.
    const growthBtn = [...container.querySelectorAll('button.pl-row-toggle')].find(
      (b) => b.textContent?.includes('Growth Rings'),
    ) as HTMLButtonElement;
    act(() => growthBtn.click());
    expect(container.textContent).not.toContain('Slow character evolution');
    act(() => growthBtn.click());
    expect(container.textContent).toContain('Slow character evolution');

    const collapseDetails = [...container.querySelectorAll('button')].find(
      (b) => b.textContent === 'Collapse all details',
    )!;
    act(() => collapseDetails.click());
    expect(container.textContent).not.toContain('Slow character evolution');
    expect(container.textContent).toContain(
      'Adds lived experience as slow layers without rewriting who they are.',
    );
    expect(container.textContent).toContain('How often');

    const expandDetails = [...container.querySelectorAll('button')].find(
      (b) => b.textContent === 'Expand all details',
    )!;
    act(() => expandDetails.click());
    expect(container.textContent).toContain('Slow character evolution');
  });

  it('auto-expands target group and highlights parent when cross-subgroup dependency chip is clicked', () => {
    const timeHeader = [...container.querySelectorAll('.pl-group-head-btn')].find(
      (b) => b.textContent?.includes('Time & World'),
    ) as HTMLButtonElement;
    act(() => timeHeader.click());
    expect(
      container.querySelector('input[aria-label="Passage of Time"]'),
    ).toBeNull();

    const dreamsChip = [...container.querySelectorAll('button.pl-chip-link')].find(
      (b) => b.textContent?.includes('needs Passage of Time'),
    ) as HTMLButtonElement;
    act(() => dreamsChip.click());

    expect(
      container.querySelector('input[aria-label="Passage of Time"]'),
    ).not.toBeNull();
    expect(container.querySelector('.pl-row-highlight')).not.toBeNull();
  });

  it('moves 18+ themes out of PorchLifeSettings into AdultThemesCard (General parity)', () => {
    expect(
      container.querySelector('input[aria-label="18+ themes"]'),
    ).toBeNull();

    const adultRootEl = document.createElement('div');
    document.body.appendChild(adultRootEl);
    const adultRoot = createRoot(adultRootEl);
    act(() => {
      adultRoot.render(createElement(AdultThemesCard));
    });
    expect(
      adultRootEl.querySelector('input[aria-label="18+ themes"]'),
    ).not.toBeNull();
    act(() => adultRoot.unmount());
    adultRootEl.remove();
  });
});
