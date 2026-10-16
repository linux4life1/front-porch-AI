// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web creator's Interview card (the end of the Output step), on a form
// held the way the page holds it. The relay's GET /api/chargen/interview is
// stood in for here (its own test covers the wording); the card shows those
// rows, locked until they arrive, with the two conditional pills; typing
// marks a row edited and puts the list on the form; a new voice rewords the
// rows not edited; Sex rewords once its typing pauses; remove spares the
// conditional rows; Add stops at twelve; Reset is the untouched set again;
// a drag on the handle reorders live; the phone has its own copy. The
// create body is in chargenForm.test.ts, the whole flow in the browser
// journey.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_FORM, type ChargenForm } from './chargenForm';
import {
  addRow,
  isStandardList,
  removeRow,
  rowsFrom,
  type InterviewRow,
  type StandardQuestion,
} from './interviewRows';

const KEYS = [
  'voice', 'wants', 'wound', 'relationship', 'social', 'pressure',
  'attraction', 'joy', 'living', 'intimacy', 'appearance',
];
const conditionOf = (key: string) => (key === 'relationship' ? 'relationship' : key === 'intimacy' ? 'nsfw' : null);

/** Each GET waits until the test answers it, worded for its own query. */
const gets: { query: URLSearchParams; answer: () => void; fail: () => void }[] = [];
vi.mock('../../api/client', () => ({
  api: {
    get: (path: string) =>
      new Promise((resolve, reject) => {
        const query = new URLSearchParams(path.split('?')[1] ?? '');
        const p = query.get('perspective');
        const sex = query.get('sex') ?? '';
        const she = /^f/i.test(sex);
        gets.push({
          query,
          answer: () =>
            resolve({
              cap: 12,
              pronouns: she ? { subject: 'she', possessive: 'her' } : { subject: 'they', possessive: 'their' },
              rows: KEYS.map((key) => ({ key, condition: conditionOf(key), text: `${key} in ${p} ${query.get('tense')}` })),
            }),
          fail: () => reject(new Error('offline')),
        });
      }),
  },
  ApiError: class ApiError extends Error {},
}));

const { InterviewCard } = await import('./InterviewCard');

let container: HTMLDivElement;
let root: Root;
let form: ChargenForm;
let setForm: (p: Partial<ChargenForm>) => void;

function Harness({ initial }: { initial: ChargenForm }) {
  const [f, setF] = useState(initial);
  form = f;
  setForm = (p) => setF((cur) => ({ ...cur, ...p }));
  return createElement(InterviewCard, { form: f, set: setForm });
}

async function render(width: number, over: Partial<ChargenForm> = {}) {
  (window as { innerWidth: number }).innerWidth = width;
  act(() => {
    root.render(createElement(Harness, { initial: { ...DEFAULT_FORM, ...over } }));
  });
  await settle();
}

async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}

async function answerLast() {
  await act(async () => {
    gets.at(-1)!.answer();
  });
  await settle();
}

const rowsShown = () => Array.from(container.querySelectorAll<HTMLDivElement>('[data-testid="interview-row"]'));
const textOf = (i: number) => rowsShown()[i].querySelector('textarea')!.value;
const button = (name: RegExp) => {
  const b = Array.from(container.querySelectorAll('button')).find(
    (x) => name.test(x.getAttribute('aria-label') ?? '') || name.test(x.textContent ?? ''),
  );
  if (!b) throw new Error(`no button ${name}`);
  return b as HTMLButtonElement;
};
const keys = () => (form.interviewQuestions ?? []).map((r) => r.key ?? r.text);

function type(el: HTMLTextAreaElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!.call(el, value);
  act(() => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
}

function pointer(el: Element, type: string, clientY: number) {
  act(() => {
    el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientY, button: 0 }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  gets.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

describe('InterviewCard', () => {
  it('shows the relay\'s questions for the voice, locked until they arrive, with the two conditional pills', async () => {
    await render(1280);
    expect(gets).toHaveLength(1);
    expect(gets[0].query.get('perspective')).toBe('first');
    expect(gets[0].query.get('tense')).toBe('present');
    expect(container.textContent).toContain('Loading the questions…');
    expect(button(/^Add a question$/).disabled).toBe(true);

    await answerLast();
    expect(rowsShown()).toHaveLength(11);
    expect(textOf(0)).toBe('voice in first present');
    expect(container.textContent).toContain('Answered in first person, present');
    expect(container.textContent).toContain('Follows Narrative voice above.');
    const pills = Array.from(container.querySelectorAll('.cg-iv-cond')).map((p) => p.textContent);
    expect(pills).toEqual(['Asked only when a relationship is set', 'Asked only when 18+ is on']);
    // Conditional rows carry a spacer, not a remove button.
    expect(container.querySelectorAll('button.cg-iv-remove')).toHaveLength(9);
    expect(rowsShown()[3].querySelector('button.cg-iv-remove')).toBeNull();
    expect(button(/^Add a question$/).disabled).toBe(false);
    expect(container.textContent).toContain(
      '11 of 12 · remove them all and the profile comes straight from your settings, no interview',
    );
    expect(form.interviewQuestions).toBeNull();
  });

  it('typing marks a row edited; a new voice rewords only the rows not edited', async () => {
    await render(1280);
    await answerLast();
    type(rowsShown()[1].querySelector('textarea')!, 'What does she want from the sea?');
    expect(rowsShown()[1].classList.contains('edited')).toBe(true);
    expect(rowsShown()[1].textContent).toContain('Edited · kept as written');
    expect(form.interviewQuestions![1]).toMatchObject({ key: 'wants', text: 'What does she want from the sea?', condition: null });

    // An edited conditional row keeps its condition.
    type(rowsShown()[3].querySelector('textarea')!, 'Who is {{user}} to her?');
    expect(form.interviewQuestions![3]).toMatchObject({ key: 'relationship', condition: 'relationship' });

    act(() => setForm({ narrativePerspective: 'third' }));
    await settle();
    expect(gets.at(-1)!.query.get('perspective')).toBe('third');
    await answerLast();
    expect(textOf(0)).toBe('voice in third present');
    expect(textOf(1)).toBe('What does she want from the sea?');
    expect(textOf(3)).toBe('Who is {{user}} to her?');
    expect(textOf(4)).toBe('social in third present');

    act(() => setForm({ narrativeTense: 'past' }));
    await settle();
    expect(gets.at(-1)!.query.get('tense')).toBe('past');
    await answerLast();
    expect(textOf(0)).toBe('voice in third past');
    expect(textOf(1)).toBe('What does she want from the sea?');
  });

  it('asks again for Sex once its typing pauses, and names whose words are quoted', async () => {
    await render(1280, { narrativePerspective: 'third' });
    await answerLast();
    expect(container.textContent).toContain('Their own words are quoted when they speak.');
    const before = gets.length;
    act(() => setForm({ sex: 'F' }));
    act(() => setForm({ sex: 'Fe' }));
    act(() => setForm({ sex: 'Female' }));
    await settle();
    expect(gets).toHaveLength(before);
    await act(async () => {
      await new Promise((r) => setTimeout(r, 300));
    });
    expect(gets).toHaveLength(before + 1);
    expect(gets.at(-1)!.query.get('sex')).toBe('Female');
    await answerLast();
    expect(container.textContent).toContain('Follows Narrative voice above. Her own words are quoted when she speaks.');
  });

  it('a failed load says so and tries again on a tap', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await render(1280);
    await act(async () => {
      gets[0].fail();
    });
    await settle();
    expect(container.textContent).toContain('The questions could not be loaded.');
    expect(warn).toHaveBeenCalled();
    await click(button(/^Try again$/));
    expect(gets).toHaveLength(2);
    await answerLast();
    expect(rowsShown()).toHaveLength(11);
    expect(container.textContent).not.toContain('could not be loaded');
  });

  it('removes a normal row, adds up to twelve, then Reset is the standard set again', async () => {
    await render(1280);
    await answerLast();
    await click(button(/^Remove question 1$/));
    expect(rowsShown()).toHaveLength(10);
    expect(keys()[0]).toBe('wants');

    await click(button(/^Add a question$/));
    await click(button(/^Add a question$/));
    expect(rowsShown()).toHaveLength(12);
    expect(document.activeElement).toBe(rowsShown()[11].querySelector('textarea'));
    type(rowsShown()[11].querySelector('textarea')!, 'What is in the coat pocket?');
    expect(form.interviewQuestions!.at(-1)).toMatchObject({ key: null, text: 'What is in the coat pocket?', condition: null });
    expect(button(/^Add a question$/).disabled).toBe(true);
    expect(container.textContent).toContain('12 of 12');

    await click(button(/^Reset to the standard questions$/));
    expect(form.interviewQuestions).toBeNull();
    expect(rowsShown()).toHaveLength(11);
    expect(textOf(0)).toBe('voice in first present');
    expect(container.querySelector('.cg-iv-row.edited')).toBeNull();
  });

  it('the count caption says no interview once only the conditional rows are left', async () => {
    // Grok, 2026-10-14: the conditional rows cannot be removed, so the hint
    // to remove them all would be a lie once nothing else is left.
    await render(1280);
    await answerLast();
    for (let i = 0; i < 3; i++) await click(button(/^Remove question 1$/));
    for (let i = 0; i < 5; i++) await click(button(/^Remove question 2$/));
    await click(button(/^Remove question 3$/));
    expect(rowsShown()).toHaveLength(2);
    expect(keys()).toEqual(['relationship', 'intimacy']);
    expect(container.textContent).toContain('2 of 12 · no interview: the profile comes straight from your settings');
  });

  it('a new voice locks the rows until the matching set arrives', async () => {
    // Grok, 2026-10-14: the pill followed the form at once while the rows
    // kept the old wording and stayed editable until the fetch returned.
    await render(1280);
    await answerLast();
    expect(rowsShown()[0].querySelector('textarea')!.disabled).toBe(false);
    await act(async () => {
      setForm({ narrativePerspective: 'third' });
    });
    await settle();
    expect(container.textContent).toContain('Answered in third person, present');
    expect(rowsShown()[0].querySelector('textarea')!.disabled).toBe(true);
    expect(button(/^Add a question$/).disabled).toBe(true);
    await answerLast();
    expect(rowsShown()[0].querySelector('textarea')!.disabled).toBe(false);
    expect(textOf(0)).toBe('voice in third present');
  });

  it('a drag on the handle reorders the rows as the pointer passes them', async () => {
    // Each row 50px tall, 60px apart, in the order the page shows them.
    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockImplementation(function (this: HTMLElement) {
      const i = Array.from(this.parentElement?.children ?? []).indexOf(this);
      return { top: i * 60, height: 50, bottom: i * 60 + 50, left: 0, right: 0, width: 0, x: 0, y: i * 60, toJSON() {} };
    });
    await render(390);
    await answerLast();
    const list = container.querySelector('[data-testid="interview-rows"]')!;
    const handle = (i: number) => rowsShown()[i].querySelector('.cg-iv-handle')!;

    // Appearance (the last row) to the top, live, before the pointer lifts.
    pointer(handle(10), 'pointerdown', 625);
    // 400 is above row 7's middle (445), below row 6's (385).
    pointer(list, 'pointermove', 400);
    expect(keys().indexOf('appearance')).toBe(7);
    pointer(list, 'pointermove', 5);
    expect(keys()[0]).toBe('appearance');
    pointer(list, 'pointerup', 5);
    expect(textOf(0)).toBe('appearance in first present');

    // Back where it was: the untouched set, so the form holds nothing.
    pointer(handle(0), 'pointerdown', 25);
    pointer(list, 'pointermove', 640);
    pointer(list, 'pointerup', 640);
    expect(form.interviewQuestions).toBeNull();

    // A move after the pointer lifted changes nothing.
    pointer(list, 'pointermove', 5);
    expect(form.interviewQuestions).toBeNull();
  });

  it('the arrow keys on a handle move its row and keep the focus on it', async () => {
    await render(1280);
    await answerLast();
    const handle = rowsShown()[1].querySelector<HTMLButtonElement>('.cg-iv-handle')!;
    handle.focus();
    act(() => {
      handle.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));
    });
    expect(keys().slice(0, 2)).toEqual(['wants', 'voice']);
    expect(document.activeElement).toBe(rowsShown()[0].querySelector('.cg-iv-handle'));
  });

  it('the phone has its own copy: a short intro, Reset, the short count, no caption', async () => {
    await render(390, { narrativePerspective: 'third', narrativeTense: 'past' });
    await answerLast();
    const text = container.textContent ?? '';
    expect(text).toContain('Asked before the profile is written. Each question is a model call. Voice first, appearance last works best.');
    expect(text).not.toContain('The character is interviewed before');
    expect(text).toContain('Answered in third person, past');
    expect(text).not.toContain('Follows Narrative voice above.');
    expect(text).toContain('11 of 12 · none means no interview');
    const reset = button(/^Reset to the standard questions$/);
    expect(reset.textContent).toBe('Reset');

    act(() => root.unmount());
    root = createRoot(container);
    await render(1280, { narrativePerspective: 'third', narrativeTense: 'past' });
    await answerLast();
    expect(container.textContent).toContain('The character is interviewed before the profile is written.');
    expect(button(/^Reset to the standard questions$/).textContent).toBe('Reset to the standard questions');
    expect(container.textContent).toContain('Follows Narrative voice above. Their own words are quoted when they speak.');
  });
});

describe('interview rows', () => {
  const standard: StandardQuestion[] = KEYS.map((key) => ({ key, condition: conditionOf(key), text: key }));

  it('a conditional row is never removed, and Add refuses at the cap', () => {
    const rows = rowsFrom(standard);
    expect(removeRow(rows, 'std-relationship')).toBe(rows);
    expect(removeRow(rows, 'std-intimacy')).toBe(rows);
    expect(removeRow(rows, 'std-voice')).toHaveLength(10);
    const full = addRow(rows);
    expect(full).toHaveLength(12);
    expect(addRow(full)).toBe(full);
  });

  it('only the untouched set in order counts as the standard list', () => {
    const rows = rowsFrom(standard);
    expect(isStandardList(rows, standard)).toBe(true);
    expect(isStandardList([...rows].reverse(), standard)).toBe(false);
    expect(isStandardList(rows.slice(1), standard)).toBe(false);
    const edited: InterviewRow[] = rows.map((r, i) => (i === 0 ? { ...r, text: 'x' } : r));
    expect(isStandardList(edited, standard)).toBe(false);
  });
});
