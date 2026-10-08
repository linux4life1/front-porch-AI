// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The clock-off line in the shared Needs forms (the character editor and
// creator's Needs section, and an alternate greeting's Needs block): shown
// only while Porch Life's Passage of Time is off. Desktop twin:
// test/ui/widgets/needs_clock_off_note_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { GreetingSeedForm } from '../GreetingSeedForm';
import { NeedsClockOffNote } from './NeedsClockOffNote';
import { NeedsFormSection } from './NeedsFormSection';
import { REALISM_DEFAULTS } from './realismTypes';

const LINE = 'With Passage of time off, hunger, bathroom and energy wear a little each reply; the rest move only when the story says so.';

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

function render(el: ReturnType<typeof createElement>) {
  act(() => root.render(el));
}

const note = () => container.querySelector('.needs-clock-off');

describe('the clock-off line in the Needs forms', () => {
  it('sits right under the card Needs switch while the clock is off', () => {
    const v = { ...REALISM_DEFAULTS, needsSimEnabled: true };
    render(createElement(NeedsFormSection, { v, set: () => {}, clockOn: false }));
    const toggle = container.querySelector('label.realism-toggle');
    expect(toggle?.textContent).toContain('Needs simulation');
    expect(toggle?.nextElementSibling).toBe(note());
    expect(note()?.textContent).toBe(LINE);

    render(createElement(NeedsFormSection, { v, set: () => {}, clockOn: true }));
    expect(note()).toBeNull();
  });

  it("sits under an alternate greeting's Needs heading while the clock is off", () => {
    const props = { seed: {}, onChange: () => {}, showNeeds: true };
    render(createElement(GreetingSeedForm, { ...props, clockOn: false }));
    const heading = [...container.querySelectorAll('h4.realism-head')].find(
      (h) => h.textContent === 'Needs Simulation',
    );
    expect(heading?.nextElementSibling).toBe(note());
    expect(note()?.textContent).toBe(LINE);

    render(createElement(GreetingSeedForm, { ...props, clockOn: true }));
    expect(note()).toBeNull();
  });

  it('shows only for an explicit off, never for a setting not read yet', () => {
    render(createElement(NeedsClockOffNote, { clockOn: undefined as unknown as boolean }));
    expect(note()).toBeNull();
    render(createElement(NeedsClockOffNote, { clockOn: false }));
    expect(note()?.textContent).toBe(LINE);
  });
});
