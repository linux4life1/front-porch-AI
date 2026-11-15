// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PR 7d: the persona page's JSON file pair. The desktop persona page has
// "Import from JSON" and a per-persona export; the PWA carries the same
// affordances over POST /api/personas/import (raw document body) and
// GET /api/personas/<id>/export.json (server-named download). These pin
// the page's wiring: the hidden file input feeds api.upload and the row's
// ⤓ saves the download under the server's name, and the desktop's status
// copy shows on success and on an unrecognized format.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const upload = vi.fn();
const getForFile = vi.fn();
const get = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) => get(path),
    post: vi.fn(),
    upload: (path: string, file: File) => upload(path, file),
    getForFile: (path: string, fallback: string) => getForFile(path, fallback),
  },
  ApiError: class ApiError extends Error {
    constructor(message: string, readonly status: number) {
      super(message);
    }
  },
}));

import { PersonaManager } from './PersonaManager';

const personas = [
  { id: 'p1', label: 'Ada', name: 'Ada Lovelace', active: false, default: true },
  { id: 'p2', label: 'Kit', name: 'Kit', active: true, default: false },
];

describe('PersonaManager JSON import/export', () => {
  let root: Root;
  let host: HTMLDivElement;

  beforeEach(() => {
    get.mockReset().mockResolvedValue({ personas });
    upload.mockReset();
    getForFile.mockReset();
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);
  });

  afterEach(() => {
    act(() => root.unmount());
    host.remove();
    document.body.innerHTML = '';
  });

  const flush = () => act(async () => { await Promise.resolve(); });

  it('sends the picked file to /api/personas/import and shows the desktop copy', async () => {
    await act(async () => {
      root.render(createElement(PersonaManager));
    });
    await flush();

    const input = host.querySelector<HTMLInputElement>('[data-testid="persona-import-file"]')!;
    const file = new File(['{"name":"New","description":"hi"}'], 'new.json', {
      type: 'application/json',
    });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });

    upload.mockResolvedValue({ imported: 'New', personas: [...personas] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(upload).toHaveBeenCalledWith('/api/personas/import', file);
    expect(host.textContent).toContain('Imported "New" successfully');
    // The input resets so re-picking the same file fires change again.
    expect(input.value).toBe('');
  });

  it('surfaces the server\'s unrecognized-format message', async () => {
    await act(async () => {
      root.render(createElement(PersonaManager));
    });
    await flush();

    const input = host.querySelector<HTMLInputElement>('[data-testid="persona-import-file"]')!;
    const file = new File(['nope'], 'junk.json', { type: 'application/json' });
    Object.defineProperty(input, 'files', { value: [file], configurable: true });

    const { ApiError } = await import('../api/client');
    upload.mockRejectedValue(new ApiError('Import failed — unrecognized format', 400));
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(host.querySelector('.error')?.textContent).toContain(
      'Import failed — unrecognized format',
    );
  });

  it('exports one persona as the server names it', async () => {
    const clicked: string[] = [];
    const origClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function (this: HTMLAnchorElement) {
      clicked.push(this.download);
    };
    URL.createObjectURL = vi.fn(() => 'blob:fake');
    URL.revokeObjectURL = vi.fn();

    try {
      await act(async () => {
        root.render(createElement(PersonaManager));
      });
      await flush();

      getForFile.mockResolvedValue({
        blob: new Blob(['{}']),
        fileName: 'Ada_Lovelace_FPAIpersona.json',
      });
      const exportBtn = host.querySelector<HTMLButtonElement>(
        'button[aria-label="Export Ada as JSON"]',
      )!;
      await act(async () => {
        exportBtn.click();
        await Promise.resolve();
        await Promise.resolve();
      });

      expect(getForFile).toHaveBeenCalledWith(
        '/api/personas/p1/export.json',
        'Ada_Lovelace_FPAIpersona.json',
      );
      expect(clicked).toEqual(['Ada_Lovelace_FPAIpersona.json']);
    } finally {
      HTMLAnchorElement.prototype.click = origClick;
    }
  });
});
