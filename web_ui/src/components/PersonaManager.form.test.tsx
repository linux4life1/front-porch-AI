// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The persona page's form and its failure states, from a phone report:
// "+ New Persona" opened its form under a grid of ~30 cards (it looked like
// the button did nothing), a stalled host left "Saving…" up for minutes, and
// a list read that failed showed "No personas yet" as if the library were
// empty. The form now replaces the list (the desktop page's own behaviour),
// writes are bounded, and a failed read says so.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn();
const get = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => get(path),
    post: (path: string, body?: unknown, opts?: unknown) => post(path, body, opts),
    upload: vi.fn(),
    getForFile: vi.fn(),
  },
  isTimeout: (e: unknown) => e instanceof DOMException && e.name === 'TimeoutError',
  ApiError: class ApiError extends Error {
    constructor(message: string, readonly status: number) {
      super(message);
    }
  },
}));

import { PersonaManager } from './PersonaManager';

const personas = [
  {
    id: 'p1', label: 'Ada', name: 'Ada Lovelace', title: 'Mathematician',
    description: 'Writes poetry about steam engines.', hasAvatar: false, active: true, default: true,
  },
  {
    id: 'p2', label: 'Kit', name: 'Kit', title: '',
    description: '', hasAvatar: false, active: false, default: false,
  },
];

describe('PersonaManager form and failures', () => {
  let root: Root;
  let host: HTMLDivElement;

  beforeEach(() => {
    post.mockReset();
    get.mockReset().mockResolvedValue({ personas });
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
  });

  afterEach(() => {
    act(() => root.unmount());
    host.remove();
    document.body.innerHTML = '';
  });

  const settle = () =>
    act(async () => {
      for (let i = 0; i < 6; i++) await Promise.resolve();
    });
  const render = async () => {
    await act(async () => {
      root.render(createElement(PersonaManager));
    });
    await settle();
  };
  const button = (text: string) =>
    [...host.querySelectorAll('button')].find((b) => b.textContent?.trim() === text)!;
  const type = (el: HTMLInputElement | HTMLTextAreaElement, value: string) => {
    const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement : HTMLInputElement;
    Object.getOwnPropertyDescriptor(proto.prototype, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const fillNew = async (name: string, text: string) => {
    await act(async () => button('+ New Persona').click());
    const inputs = host.querySelectorAll<HTMLInputElement>('.persona-edit input');
    await act(async () => {
      type(inputs[1], name);
      type(host.querySelector<HTMLTextAreaElement>('.persona-edit textarea')!, text);
    });
  };
  const timeout = () => new DOMException('The operation timed out.', 'TimeoutError');

  it('New Persona swaps the list for the Create Persona form, like the desktop page', async () => {
    await render();
    expect(host.querySelector('.persona-grid')).toBeTruthy();
    await act(async () => button('+ New Persona').click());
    // The form is the page now: no grid, no hero, no page actions to scroll past.
    expect(host.querySelector('.persona-edit')).toBeTruthy();
    expect(host.querySelector('.persona-grid')).toBeNull();
    expect(host.querySelector('.persona-hero')).toBeNull();
    expect(host.querySelector('h3')?.textContent).toBe('Create Persona');
    const labels = [...host.querySelectorAll('.persona-edit label')].map(
      (l) => l.firstChild?.textContent?.trim(),
    );
    expect(labels).toEqual(['Title', 'Name', 'Birthday', 'Persona Text (injected into AI context)']);
    expect(button('Save Persona').disabled).toBe(true); // Name is required, and starts empty
    await act(async () =>
      host.querySelector<HTMLButtonElement>('button[aria-label="Back to personas"]')!.click(),
    );
    expect(host.querySelector('.persona-edit')).toBeNull();
    expect(host.querySelector('.persona-grid')).toBeTruthy();
  });

  it('a list read that fails says so and retries, never "No personas yet"', async () => {
    get.mockReset().mockRejectedValueOnce(timeout()).mockResolvedValue({ personas });
    await render();
    expect(host.textContent).not.toContain('No personas yet');
    expect(host.querySelector('[role="alert"]')?.textContent).toContain('Could not load your personas');
    await act(async () => button('Try again').click());
    await settle();
    expect(host.querySelector('[role="alert"]')).toBeNull();
    expect(host.querySelectorAll('.persona-grid li')).toHaveLength(2);
  });

  it('a save the host never answers ends in an error, keeps the text, and re-reads the list', async () => {
    await render();
    await fillNew('Wren', 'Tall, quiet, reads a lot.');
    post.mockRejectedValueOnce(timeout());
    get.mockClear();
    await act(async () => button('Save Persona').click());
    await settle();
    expect(post).toHaveBeenCalledWith('/api/personas/create', {
      title: '', name: 'Wren', persona: 'Tall, quiet, reads a lot.', birthday: '',
    }, { timeoutMs: 20_000 });
    expect(host.querySelector('.error')?.textContent).toContain('did not answer within 20 seconds');
    // Not stuck on "Saving…", and nothing typed was thrown away.
    expect(button('Save Persona').disabled).toBe(false);
    expect(host.querySelector<HTMLTextAreaElement>('.persona-edit textarea')!.value)
      .toBe('Tall, quiet, reads a lot.');
    expect(get).toHaveBeenCalledWith('/api/personas');
  });

  it('a timed-out create that landed late is not saved a second time', async () => {
    await render();
    await fillNew('Wren', 'Tall, quiet, reads a lot.');
    post.mockRejectedValueOnce(timeout());
    // The re-read after the timeout finds the persona the host finished late.
    const wren = {
      id: 'p3', label: 'Wren', name: 'Wren', title: '', description: 'Tall, quiet, reads a lot.',
      hasAvatar: false, active: true, default: true,
    };
    get.mockResolvedValue({ personas: [...personas, wren] });
    await act(async () => button('Save Persona').click());
    await settle();
    post.mockClear();
    await act(async () => button('Save Persona').click());
    await settle();
    expect(post).not.toHaveBeenCalled();
    expect(host.querySelector('.persona-edit')).toBeNull();
    expect(host.querySelector('[data-testid="persona-save-notice"]')?.textContent)
      .toBe('Persona saved successfully');
  });
});
