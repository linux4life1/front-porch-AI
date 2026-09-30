// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web Reprocess Needs modal shows only the speaker's ENABLED needs
// (/workspace/sow/rn-spec.md items 7-8): same copy and one/zero states as the
// desktop dialog, desktop's exact intro + placeholder, never submits a key
// outside enabledNeeds. Renders the real component.
//
// Props per AMENDMENT 2 item 3: enabledNeeds, speaker, speakerName (the
// per-message facade field is chips.enabledNeeds).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, type ComponentType } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ReprocessNeedsModal } from './ReprocessNeedsModal';
import { NEED_LABELS } from './chatTypes';

const ALL = ['hunger', 'bladder', 'energy', 'social', 'fun', 'hygiene', 'comfort'];
const FIVE = ['hunger', 'bladder', 'energy', 'social', 'comfort'];

const DESKTOP_INTRO =
  'Enter your critique to correct the Needs Simulation deltas. The Realism Director will re-evaluate the scene based on this input.';
const DESKTOP_HINT = 'e.g., They rested on the sofa — energy should have improved.';
const NONE_SELECTED = 'Nothing selected — every need shown here is re-evaluated.';
const NULL_STATE = "There's nothing to reprocess for this message.";
const SOME_SELECTED = 'Only the selected needs change. The others keep their current deltas.';

let container: HTMLDivElement;
let root: Root;

const Modal = ReprocessNeedsModal as unknown as ComponentType<Record<string, unknown>>;

function render(enabledNeeds: string[], onSubmit = vi.fn(async () => {})) {
  act(() => {
    root.render(
      createElement(Modal, {
        onSubmit,
        onClose: vi.fn(),
        enabledNeeds,
        speaker: 'Mara',
        speakerName: 'Mara',
      }),
    );
  });
  return onSubmit;
}

// AMENDMENT 2 items 4-5: ONE string, no {name}; exactly one button, Close.
function expectNullState() {
  expect(text()).toContain(NULL_STATE);
  expect(text()).not.toContain('Mara');
  expect(container.querySelector('textarea')).toBeNull();
  expect(needChipLabels()).toEqual([]);
  expect(button('Cancel')).toBeUndefined();
  expect(button('Reprocess')).toBeUndefined();
  expect(buttons().map((b) => b.textContent?.trim())).toEqual(['Close']);
}

const text = () => container.textContent ?? '';
const buttons = () => Array.from(container.querySelectorAll('button'));
const button = (label: string) => buttons().find((b) => b.textContent?.trim() === label);
const needChipLabels = () => {
  const labels = new Set(Object.values(NEED_LABELS));
  return buttons()
    .map((b) => b.textContent?.trim() ?? '')
    .filter((t) => labels.has(t));
};

function typeCritique(value: string) {
  const ta = container.querySelector('textarea') as HTMLTextAreaElement;
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')?.set;
    setter?.call(ta, value);
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function clickAsync(el: Element | undefined) {
  expect(el).toBeDefined();
  await act(async () => {
    el!.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  });
}

describe('ReprocessNeedsModal enabled needs only', () => {
  beforeEach(() => {
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });
  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('F1 offers only the enabled needs (Hygiene+Fun off -> 5 chips)', () => {
    render(FIVE);
    expect(needChipLabels()).toEqual(FIVE.map((k) => NEED_LABELS[k]));
    expect(button('Hygiene')).toBeUndefined();
    expect(button('Fun')).toBeUndefined();
  });

  it('F2 exact helper copy: nothing selected, then one selected', async () => {
    render(FIVE);
    expect(text()).toContain(NONE_SELECTED);
    await clickAsync(button('Energy'));
    expect(text()).toContain(SOME_SELECTED);
  });

  it("F3 intro and placeholder match desktop's exact text", () => {
    render(ALL);
    expect(text()).toContain(DESKTOP_INTRO);
    expect(container.querySelector('textarea')?.placeholder).toBe(DESKTOP_HINT);
  });

  it('F4 exactly one enabled: no scope block, the one-line message, submits []', async () => {
    const onSubmit = render(['hunger']);
    expect(text()).toContain('Only Hunger is on for Mara, so only Hunger is re-evaluated.');
    expect(text()).not.toContain('Limit to these needs');
    expect(needChipLabels()).toEqual([]);
    typeCritique('She ate; hunger up.');
    await clickAsync(button('Reprocess'));
    expect(onSubmit).toHaveBeenCalledTimes(1);
    expect(onSubmit.mock.calls[0]).toEqual(['She ate; hunger up.', []]);
  });

  it('F5 zero enabled (card now all off): the one null string, Close only', () => {
    render([]);
    expectNullState();
  });

  it('F6 never submits a key outside enabledNeeds', async () => {
    const onSubmit = render(FIVE);
    for (const label of ['Hygiene', 'Fun', 'Energy']) {
      const b = button(label);
      if (b) await clickAsync(b);
    }
    typeCritique('Rested; energy up.');
    await clickAsync(button('Reprocess'));
    expect(onSubmit).toHaveBeenCalledTimes(1);
    const sent = onSubmit.mock.calls[0][1] as string[];
    expect(sent.filter((k) => !FIVE.includes(k))).toEqual([]);
    expect(sent).toEqual(['energy']);
  });
});
