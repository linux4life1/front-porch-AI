// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../api/client';
import { PackGrid } from './PackGrid';

const get = vi.fn();
const post = vi.fn();

vi.mock('../../api/client', () => ({
  ApiError: class ApiError extends Error {
    status: number;
    constructor(status: number, message: string) {
      super(message);
      this.status = status;
    }
  },
  api: {
    get: (...args: unknown[]) => get(...args),
    post: (...args: unknown[]) => post(...args),
  },
}));

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
  get.mockReset();
  post.mockReset();
});

function render() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(PackGrid));
  });
}

describe('PackGrid', () => {
  it('shows filenames and verdicts and does not draw image bytes', async () => {
    get.mockResolvedValue({
      running: true,
      filenames: ['joy.png'],
      verdicts: [
        { emotion: 'joy', samePerson: true, expressionMatches: false, note: 'flat' },
      ],
    });
    render();
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toContain('joy.png');
    expect(container.textContent).toContain('flat');
    expect(container.querySelector('img')).toBeNull();
    const cancel = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Cancel pack');
    act(() => cancel?.click());
    expect(post).toHaveBeenCalledWith('/api/image/expression-pack/cancel', {});
  });

  it('stays blank when another account has no pack', async () => {
    get.mockRejectedValue(new ApiError(404, 'No expression pack', {}));
    render();
    await act(async () => {
      await Promise.resolve();
    });
    expect(container.textContent).toBe('');
    expect(container.querySelector('img')).toBeNull();
  });
});
