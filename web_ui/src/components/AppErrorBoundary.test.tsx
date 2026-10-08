// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A crashing screen must leave a way out instead of a blank page.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter, Route, Routes, useNavigate } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AppErrorBoundary } from './AppErrorBoundary';

let container: HTMLDivElement;
let root: Root;
let go: (path: string) => void;

function Boom(): never {
  throw new Error('bad card data');
}

function Nav() {
  go = useNavigate();
  return null;
}

describe('AppErrorBoundary', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
    vi.restoreAllMocks();
  });

  it('shows a plain-English fallback, then recovers on navigation', async () => {
    await act(async () => {
      root.render(
        createElement(
          MemoryRouter,
          { initialEntries: ['/chat'] },
          createElement(Nav),
          createElement(
            AppErrorBoundary,
            null,
            createElement(
              Routes,
              null,
              createElement(Route, { path: '/chat', element: createElement(Boom) }),
              createElement(Route, { path: '/', element: 'library' }),
            ),
          ),
        ),
      );
    });
    expect(container.textContent).toContain('Something went wrong on this screen');
    expect(container.textContent).toContain('bad card data');

    await act(async () => go('/'));
    expect(container.textContent).toBe('library');
  });
});
