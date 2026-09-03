// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Desktop Objectives sidebar has NSFW Tasks, a generate count, and a
// manual add-task row. The phone used to POST generate with neither nsfw
// nor taskCount, and had no add-task field — the Dart route already
// accepted both.
//
// Proven red: generate without nsfw/taskCount in the body fails the
// generate-posts-count-and-nsfw assertion.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));

vi.mock('../api/client', () => ({
  api: { post: (url: string, body?: unknown) => post(url, body) },
}));

const { ObjectivesPanel } = await import('./ObjectivesPanel');

let container: HTMLDivElement;
let root: Root;

const primary = {
  id: 'obj-1',
  objective: 'Find the keys',
  isPrimary: true,
  checkFrequency: 3,
  tasks: [] as { description: string; completed: boolean }[],
};

function render() {
  act(() => {
    root.render(
      createElement(ObjectivesPanel, {
        primary,
        secondary: [],
        checking: false,
        enabled: true,
        query: '',
        apply: (p) => {
          void p;
        },
      }),
    );
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
  post.mockClear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ObjectivesPanel', () => {
  it('generate posts taskCount and nsfw', () => {
    render();
    expect(container.textContent).toContain('NSFW tasks');
    expect(container.querySelector('select[aria-label="Task count"]')).toBeTruthy();

    click('Generate tasks');
    expect(post).toHaveBeenCalledWith('/api/chat/tools/objective', {
      action: 'generate',
      id: 'obj-1',
      taskCount: 5,
      nsfw: false,
    });

    const nsfw = container.querySelector('input[type="checkbox"]') as HTMLInputElement;
    act(() => {
      nsfw.click();
    });
    const count = container.querySelector('select[aria-label="Task count"]') as HTMLSelectElement;
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')!.set!;
      setter.call(count, '8');
      count.dispatchEvent(new Event('change', { bubbles: true }));
    });
    click('Generate tasks');
    expect(post).toHaveBeenLastCalledWith('/api/chat/tools/objective', {
      action: 'generate',
      id: 'obj-1',
      taskCount: 8,
      nsfw: true,
    });
  });

  it('Add posts a manual task', () => {
    render();
    const input = [...container.querySelectorAll('input')].find(
      (el) => el.getAttribute('placeholder') === 'Add a task manually…',
    ) as HTMLInputElement;
    expect(input).toBeTruthy();
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      setter.call(input, 'Look under the table');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    click('Add');
    expect(post).toHaveBeenCalledWith('/api/chat/tools/task', {
      action: 'add',
      id: 'obj-1',
      description: 'Look under the table',
    });
  });
});
