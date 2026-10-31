// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web Backups page lists snapshots with what they hold, restores one
// with the password step-up and the "also restore settings" choice, shows
// a waiting restore and cancels it, and only asks for a password before a
// full backup when API keys go in it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const calls: { method: string; path: string; body?: unknown }[] = [];
let pending: unknown = null;

const state = () => ({
  nightly: false,
  maxSnapshots: 10,
  dailyDays: 7,
  snapshots: [
    { id: 'front_porch_backup_1.db', created: Date.UTC(2026, 9, 30, 12), size: 2 * 1024 * 1024, hasSettings: true },
    { id: 'front_porch_backup_0.db', created: Date.UTC(2026, 9, 29, 12), size: 1024 * 1024, hasSettings: false },
  ],
  pending,
});

vi.mock('../api/client', () => ({
  api: {
    get: async (path: string) => {
      calls.push({ method: 'GET', path });
      return path === '/api/auth/state' ? { totpEnabled: false } : state();
    },
    post: async (path: string, body?: unknown) => {
      calls.push({ method: 'POST', path, body });
      if (path.endsWith('/restore')) pending = { kind: 'snapshot', created: Date.UTC(2026, 9, 30, 12), staged: 0 };
      if (path === '/api/backups/full') return { token: 'abc', fileName: 'x.fpbackup', size: 10 };
      return state();
    },
    del: async (path: string) => {
      calls.push({ method: 'DELETE', path });
      if (path === '/api/backups/pending') pending = null;
      return state();
    },
  },
  ApiError: class ApiError extends Error {
    payload: Record<string, unknown> = {};
  },
  parseApiErrorBody: (text: string) => new Error(text),
}));

const { BackupsPage } = await import('./BackupsPage');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  calls.length = 0;
  pending = null;
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(BackupsPage));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function buttons(label: string): HTMLButtonElement[] {
  return [...container.querySelectorAll('button')].filter((el) => el.textContent?.trim() === label);
}

async function type(input: HTMLInputElement, value: string) {
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(el: HTMLElement) {
  await act(async () => {
    el.click();
  });
}

it('lists each snapshot with what it holds', () => {
  expect(container.textContent).toContain('library and settings');
  expect(container.textContent).toContain('library only');
  expect(buttons('Restore')).toHaveLength(2);
});

it('restores a snapshot with settings after the password step-up, then shows it waiting', async () => {
  await click(buttons('Restore')[0]);
  const restore = buttons('Restore this backup')[0];
  expect(restore.disabled).toBe(true);
  expect(container.textContent).toContain('Also restore settings');
  await type(container.querySelector('input[type="password"]') as HTMLInputElement, 'pw');
  await click(buttons('Restore this backup')[0]);
  const post = calls.find((c) => c.method === 'POST' && c.path.endsWith('/restore'));
  expect(post?.path).toBe('/api/backups/front_porch_backup_1.db/restore');
  expect(post?.body).toEqual({ withSettings: true, currentPassword: 'pw' });
  expect(container.querySelector('[data-testid="pending-restore"]')?.textContent).toContain('library and settings');

  await click(buttons('Cancel restore')[0]);
  expect(calls.some((c) => c.method === 'DELETE' && c.path === '/api/backups/pending')).toBe(true);
  expect(container.querySelector('[data-testid="pending-restore"]')).toBeNull();
});

it('a library-only snapshot never asks to restore settings', async () => {
  await click(buttons('Restore')[1]);
  expect(container.textContent).not.toContain('Also restore settings');
  await type(container.querySelector('input[type="password"]') as HTMLInputElement, 'pw');
  await click(buttons('Restore this backup')[0]);
  const post = calls.find((c) => c.method === 'POST' && c.path.endsWith('/restore'));
  expect(post?.body).toEqual({ withSettings: false, currentPassword: 'pw' });
});

it('a full backup needs the password only when API keys go in it', async () => {
  const download = () => buttons('Download full backup')[0];
  expect(download().disabled).toBe(false);
  expect(container.querySelector('input[type="password"]')).toBeNull();
  const keys = [...container.querySelectorAll('label.checkbox')].find((l) =>
    l.textContent?.includes('Include API keys'),
  )!.querySelector('input') as HTMLInputElement;
  await click(keys);
  expect(download().disabled).toBe(true);
  await type(container.querySelector('input[type="password"]') as HTMLInputElement, 'pw');
  await click(download());
  const post = calls.find((c) => c.path === '/api/backups/full');
  expect(post?.body).toEqual({ includeSecrets: true, currentPassword: 'pw' });
});
