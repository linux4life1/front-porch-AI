// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { ReprocessNeedsModal } from './ReprocessNeedsModal';

let container: HTMLDivElement;
let root: Root;

const INTRO =
  'Enter your critique to correct the Needs Simulation deltas. The Realism Director will re-evaluate the scene based on this input.';
const PLACEHOLDER =
  'e.g., They rested on the sofa — energy should have improved.';
const EMPTY_HELPER =
  'Nothing selected — every need shown here is re-evaluated.';

type Submit = [string, string[]];

function render(props: {
  enabledNeeds: string[];
  speakerName?: string;
  onSubmit?: (critique: string, onlyNeeds: string[]) => Promise<void>;
}) {
  act(() => {
    root.render(
      createElement(ReprocessNeedsModal, {
        enabledNeeds: props.enabledNeeds,
        speakerName: props.speakerName ?? 'Aria',
        onSubmit: props.onSubmit ?? (async () => {}),
        onClose: () => {},
      }),
    );
  });
}

function typeCritique(text: string) {
  const el = container.querySelector('textarea');
  if (!el) return;
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(
      HTMLTextAreaElement.prototype,
      'value',
    )!.set!;
    setter.call(el, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

function click(label: string) {
  const btn = [...container.querySelectorAll('button')].find(
    (b) => b.textContent === label,
  );
  expect(btn, `button "${label}"`).toBeTruthy();
  act(() => {
    btn!.click();
  });
}

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

describe('ReprocessNeedsModal enabled needs', () => {
  it('renders only enabledNeeds chips', () => {
    render({
      enabledNeeds: ['hunger', 'bladder', 'energy', 'social', 'comfort'],
    });
    const labels = [...container.querySelectorAll('.need-chip')].map(
      (el) => el.textContent,
    );
    expect(labels).toEqual(['Hunger', 'Bladder', 'Energy', 'Social', 'Comfort']);
    expect(container.textContent).not.toContain('Hygiene');
    expect(container.textContent).not.toContain('Fun');
    expect(container.textContent).toContain(EMPTY_HELPER);
    expect(container.textContent).toContain(INTRO);
    expect(container.querySelector('textarea')?.placeholder).toBe(PLACEHOLDER);
  });

  it('one enabled hides chips and submits an empty scope', async () => {
    const calls: Submit[] = [];
    render({
      enabledNeeds: ['hunger'],
      onSubmit: async (critique, onlyNeeds) => {
        calls.push([critique, onlyNeeds]);
      },
    });
    expect(container.querySelectorAll('.need-chip')).toHaveLength(0);
    expect(container.textContent).toContain(
      'Only Hunger is on for Aria, so only Hunger is re-evaluated.',
    );
    typeCritique('they ate');
    click('Reprocess');
    await act(async () => {
      await Promise.resolve();
    });
    expect(calls).toEqual([['they ate', []]]);
  });

  it('zero enabled shows the message and Close only', () => {
    render({ enabledNeeds: [] });
    expect(container.textContent).toContain(
      'Aria has every need turned off, so there\'s nothing to reprocess.',
    );
    expect(container.querySelector('textarea')).toBeNull();
    expect(
      [...container.querySelectorAll('button')].some((b) => b.textContent === 'Close'),
    ).toBe(true);
    expect(
      [...container.querySelectorAll('button')].some((b) => b.textContent === 'Reprocess'),
    ).toBe(false);
  });

  it('submit never includes a disabled key', async () => {
    const calls: Submit[] = [];
    render({
      enabledNeeds: ['hunger', 'energy'],
      onSubmit: async (critique, onlyNeeds) => {
        calls.push([critique, onlyNeeds]);
      },
    });
    click('Hunger');
    typeCritique('fix hunger');
    click('Reprocess');
    await act(async () => {
      await Promise.resolve();
    });
    expect(calls[0][1]).toEqual(['hunger']);
    expect(calls[0][1]).not.toContain('hygiene');
  });
});
