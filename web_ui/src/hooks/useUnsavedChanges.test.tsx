// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A page with unsaved edits asks before a link, navigate() or a reload takes
// the user away, and a Save that navigates does not.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { useState } from 'react';
import {
  createMemoryRouter,
  Link,
  RouterProvider,
  useNavigate,
} from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UNSAVED_QUESTION, useUnsavedChanges } from './useUnsavedChanges';

function Editor() {
  const [text, setText] = useState('');
  const navigate = useNavigate();
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(text !== '');
  return (
    <div>
      {prompt}
      <h1>Editor</h1>
      <input value={text} onChange={(e) => setText(e.target.value)} />
      <Link to="/">Library</Link>
      <button
        onClick={() => {
          leaveWithoutAsking();
          navigate('/');
        }}
      >
        Save
      </button>
    </div>
  );
}

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

function field(): HTMLInputElement {
  return container.querySelector('input') as HTMLInputElement;
}

function type(value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(field(), value);
    field().dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(label: string) {
  const el = [...container.querySelectorAll('a,button')].find(
    (e) => e.textContent === label,
  ) as HTMLElement;
  await act(async () => {
    el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, button: 0 }));
  });
}

const heading = () => container.querySelector('h1')?.textContent;

function mount() {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Library page</h1> },
      { path: '/edit', element: <Editor /> },
    ],
    { initialEntries: ['/edit'] },
  );
  act(() => root.render(<RouterProvider router={router} />));
  return router;
}

describe('useUnsavedChanges', () => {
  it('leaves a clean page without asking', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    mount();
    await click('Library');
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before a link leaves typed edits, and stays on Cancel', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    mount();
    type('backstory');
    await click('Library');
    expect(confirm).toHaveBeenCalledWith(UNSAVED_QUESTION);
    expect(heading()).toBe('Editor');
    expect(field().value).toBe('backstory');
  });

  it('leaves typed edits when the user discards', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    mount();
    type('backstory');
    await click('Library');
    expect(heading()).toBe('Library page');
  });

  it('a Save that navigates does not ask', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    mount();
    type('kept');
    await click('Save');
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before a reload or tab close only while dirty', () => {
    mount();
    const clean = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(clean);
    expect(clean.defaultPrevented).toBe(false);

    type('x');
    const dirty = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(dirty);
    expect(dirty.defaultPrevented).toBe(true);
  });
});
