// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Filter models field on the phone's Installed models card — the twin
// of the desktop's My Models filter (model_manager_page.dart:364). Same
// case-insensitive substring over the filename (the wire's `name`, see
// backend_facade.localModels). The real component runs.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));

import { LocalModels } from './LocalModels';

const MODELS = [
  { name: 'alpaca-13b-Q4_K_M.gguf', path: '/m/alpaca.gguf', sizeBytes: 8e9, quant: 'Q4_K_M', paramCountB: 13, loaded: false },
  { name: 'mistral-7b-Q5_K_M.gguf', path: '/m/mistral.gguf', sizeBytes: 5e9, quant: 'Q5_K_M', paramCountB: 7, loaded: true },
];

let container: HTMLDivElement;
let root: Root;
const onError = vi.fn();

async function show() {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/models' ? { models: MODELS } : { path: '/m' }),
  );
  await act(async () => {
    root.render(createElement(LocalModels, { isLocal: true, reloadStatus: async () => {}, onError }));
  });
}

const filterBox = () =>
  container.querySelector<HTMLInputElement>('input[aria-label="Filter models"]')!;

function type(el: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, value);
  act(() => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  onError.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Filter models on the Installed models card', () => {
  it('narrows the list by a case-insensitive name substring', async () => {
    await show();
    expect(container.querySelectorAll('.model-list li')).toHaveLength(2);

    await act(async () => {
      type(filterBox(), 'MISTRAL');
    });

    const rows = Array.from(container.querySelectorAll('.model-list li'));
    expect(rows).toHaveLength(1);
    expect(rows[0].textContent).toContain('mistral-7b-Q5_K_M.gguf');
  });

  it('says "No models found" when nothing matches', async () => {
    await show();
    await act(async () => {
      type(filterBox(), 'zzz');
    });
    expect(container.querySelector('.model-list')).toBeNull();
    expect(container.textContent).toContain('No models found');
  });
});
