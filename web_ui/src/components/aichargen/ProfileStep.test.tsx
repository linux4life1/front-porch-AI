// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web creator's Profile step. A steered rewrite asks the relay with the
// texts as typed and the steer; while it streams, the Description box shows
// its text with "Writing…", Personality waits, Scenario is kept, the facts
// card dims and says it will be read again, and the step reports it is
// busy; the done event puts the new texts and facts in. Stop leaves the old
// text. Re-read asks for the facts and shows them. The 18+ row shows only
// with 18+. Chips come off and go on, and Next reads what the author left.
// The relay itself is covered by its routes test and the browser journey.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, createRef } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { WsEvent } from '../../api/ws';
import type { ProfileStepHandle } from './ProfileStep';
import { EMPTY_FACTS, type ProfileView } from './profileApi';

let emit: (e: WsEvent) => void = () => {};
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: (e: WsEvent) => void) {
      emit = cb;
    }
    connect() {}
    close() {}
  },
}));

type Call = { path: string; body: Record<string, unknown> };
const posts: Call[] = [];
vi.mock('../../api/client', () => ({
  api: {
    get: async () => ({ pending: null }),
    post: async (path: string, body: Record<string, unknown>) => {
      posts.push({ path, body });
      return path.endsWith('/stop') ? { stopped: true } : { status: 'started' };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { ProfileStep } = await import('./ProfileStep');

const VIEW: ProfileView = {
  name: 'Aria Vale',
  description: '{{char}} keeps the light.',
  personality: 'Dry and patient.',
  scenario: 'A storm closes the harbor.',
  facts: { ...EMPTY_FACTS, occupation: 'lighthouse keeper', likes: ['salt wind', 'tea'] },
  transcriptQuestions: 9,
  transcript: 'Q: Who are you?\nA: The keeper.',
  userScenario: false,
  mode: 'guided',
  nsfw: false,
  age: '34',
  writing: null,
};

let container: HTMLDivElement;
let root: Root;
const busy: boolean[] = [];
const handle = createRef<ProfileStepHandle>();

const $ = <T extends Element>(sel: string) => {
  const el = container.querySelector<T>(sel);
  if (!el) throw new Error(`missing ${sel}`);
  return el;
};
const button = (scope: Element, text: RegExp) => {
  const b = Array.from(scope.querySelectorAll('button')).find(
    (x) => text.test(x.textContent ?? '') || text.test(x.getAttribute('aria-label') ?? ''),
  );
  if (!b) throw new Error(`no button ${text}`);
  return b as HTMLButtonElement;
};
const card = (name: string) => $(`[data-testid="profile-card-${name}"]`);

function type(el: HTMLInputElement | HTMLTextAreaElement, value: string) {
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(el, value);
  act(() => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
}

function render(view: ProfileView) {
  act(() => {
    root.render(
      createElement(ProfileStep, {
        ref: handle,
        initial: view,
        onWritingChange: (w: boolean) => busy.push(w),
      }),
    );
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  busy.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ProfileStep', () => {
  it('streams a steered rewrite into its boxes, stops, and re-reads the facts', async () => {
    render(VIEW);
    expect(container.textContent).toContain('Profile');
    expect(container.textContent).toContain('9 questions, read only');

    // The author edits a box, then steers a rewrite.
    type(card('description').querySelector('textarea') as HTMLTextAreaElement, '{{char}} keeps the light, edited.');
    type($<HTMLTextAreaElement>('#cg-profile-steer'), 'Does not follow the Tsundere personality type');
    await click(button(container, /Rewrite the profile/));
    expect(posts.at(-1)).toEqual({
      path: '/api/chargen/profile/rewrite',
      body: {
        description: '{{char}} keeps the light, edited.',
        personality: 'Dry and patient.',
        scenario: 'A storm closes the harbor.',
        direction: 'Does not follow the Tsundere personality type',
      },
    });
    expect(busy.at(-1)).toBe(true);

    act(() =>
      emit({ event: 'chargen_profile_progress', field: 'description', description: 'ZZNEW tall', personality: '' }),
    );
    expect(card('description').textContent).toContain('Writing…');
    expect($('[data-testid="profile-stream-description"]').textContent).toContain('ZZNEW tall');
    expect(card('personality').textContent).toContain('Waiting for the description…');
    expect(card('scenario').textContent).toContain('Kept as it is');
    expect($('[data-testid="facts-card"]').className).toContain('dim');
    expect($('[data-testid="facts-card"]').textContent).toContain('Re-read after the rewrite');
    expect(button(container, /Re-read from the profile/).disabled).toBe(true);

    act(() =>
      emit({
        event: 'chargen_profile_progress',
        field: 'personality',
        description: 'ZZNEW tall and windburnt.',
        personality: 'ZZNEW blunt',
      }),
    );
    expect(card('personality').textContent).toContain('Writing…');
    expect($('[data-testid="profile-stream-personality"]').textContent).toContain('ZZNEW blunt');
    expect($('[data-testid="profile-stream-description"]').textContent).toContain('ZZNEW tall and windburnt.');

    act(() =>
      emit({
        event: 'chargen_profile_done',
        description: 'ZZNEW tall and windburnt.',
        personality: 'ZZNEW blunt and exact.',
        scenario: 'A storm closes the harbor.',
        facts: { ...EMPTY_FACTS, occupation: 'harbour pilot' },
      }),
    );
    expect(busy.at(-1)).toBe(false);
    expect((card('description').querySelector('textarea') as HTMLTextAreaElement).value).toBe(
      'ZZNEW tall and windburnt.',
    );
    expect(($('[data-testid="facts-card"]').querySelectorAll('input')[1] as HTMLInputElement).value).toBe(
      'harbour pilot',
    );

    // Stop leaves the text it had.
    await click(button(container, /Rewrite the profile/));
    act(() => emit({ event: 'chargen_profile_progress', field: 'description', description: 'never kept' }));
    await click(button(container, /^Stop$/));
    expect(posts.at(-1)?.path).toBe('/api/chargen/profile/stop');
    expect(container.textContent).not.toContain('never kept');
    expect((card('description').querySelector('textarea') as HTMLTextAreaElement).value).toBe(
      'ZZNEW tall and windburnt.',
    );
    expect(busy.at(-1)).toBe(false);

    // Re-read: the facts card dims, then shows what came back.
    await click(button(container, /Re-read from the profile/));
    expect(posts.at(-1)?.path).toBe('/api/chargen/profile/facts');
    expect($('[data-testid="facts-card"]').className).toContain('dim');
    act(() => emit({ event: 'chargen_facts_done', facts: { ...EMPTY_FACTS, occupation: 'net mender' } }));
    expect($('[data-testid="facts-card"]').className).not.toContain('dim');
    expect(($('[data-testid="facts-card"]').querySelectorAll('input')[1] as HTMLInputElement).value).toBe(
      'net mender',
    );
    // A saved character's events are not the pending run's.
    act(() => emit({ event: 'chargen_facts_done', characterId: '9', facts: { occupation: 'not ours' } }));
    expect(container.innerHTML).not.toContain('not ours');
  });

  it('edits the facts; Next reads what the author left; 18+ only with 18+', async () => {
    render(VIEW);
    expect(container.textContent).not.toContain('INTIMATE PREFERENCES');
    expect(container.textContent).toContain('BIRTHDAY · AGE 34');
    await click(button(container, /Remove salt wind/));
    await click(button($('[data-testid="facts-card"]'), /Add to warms to/));
    const add = $<HTMLInputElement>('input[aria-label="Add to warms to"]');
    type(add, 'hot tea');
    act(() => {
      add.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    });
    expect(handle.current!.current()!.facts.likes).toEqual(['tea', 'hot tea']);
    expect(handle.current!.current()!.texts.description).toBe('{{char}} keeps the light.');
    expect(($('[data-testid="facts-card"]').querySelectorAll('input')[4] as HTMLInputElement).readOnly).toBe(true);

    act(() => root.unmount());
    root = createRoot(container);
    render({ ...VIEW, nsfw: true });
    expect(container.textContent).toContain('INTIMATE PREFERENCES · 18+ IS ON');
  });

  it('keeps an Automated description as built while the rest is rewritten', async () => {
    render({ ...VIEW, mode: 'automated' });
    await click(button(container, /Rewrite the profile/));
    act(() => emit({ event: 'chargen_profile_progress', field: 'description', description: 'model text' }));
    expect(card('description').textContent).toContain('Kept as you built it');
    expect(card('description').textContent).not.toContain('model text');
  });
});
