// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Test kit for the phone desk: a stand-in for the API client that answers by
// route, and helpers to press, type and wait on a rendered component.

import { createElement, act, type ReactElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { expect } from 'vitest';
import type { ImageConfig } from './types';

export class FakeApiError extends Error {
  status: number;
  payload: Record<string, unknown>;
  constructor(status: number, message: string, payload: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.payload = payload;
  }
}

export interface Call {
  method: 'GET' | 'POST';
  path: string;
  body?: unknown;
}

type Answer = unknown | ((body: any, path: string) => unknown);

export const calls: Call[] = [];
let routes: Record<string, Answer> = {};

/** Failing answer: the client rejects with this status and message. */
export const refuse = (status: number, message: string, payload: Record<string, unknown> = {}) =>
  new FakeApiError(status, message, payload);

/**
 * Sets what each route answers. Keys are `GET /path` or `POST /path` without
 * the query string; a value may be a function of the request body.
 */
export function serve(map: Record<string, Answer>) {
  routes = map;
}

export function reset() {
  calls.length = 0;
  routes = {};
}

async function answer(method: 'GET' | 'POST', full: string, body?: unknown) {
  calls.push({ method, path: full, body });
  const key = `${method} ${full.split('?')[0]}`;
  if (!(key in routes)) throw new FakeApiError(404, `no route ${key}`);
  const value = routes[key];
  const result = typeof value === 'function' ? await (value as (b: unknown, p: string) => unknown)(body, full) : value;
  if (result instanceof FakeApiError) throw result;
  return result;
}

export const clientMock = {
  ApiError: FakeApiError,
  api: {
    get: (path: string) => answer('GET', path),
    post: (path: string, body?: unknown) => answer('POST', path, body),
  },
};

export const posts = (path: string) =>
  calls.filter((c) => c.method === 'POST' && c.path.split('?')[0] === path);
export const gets = (path: string) =>
  calls.filter((c) => c.method === 'GET' && c.path.split('?')[0] === path);

// ---- rendering -------------------------------------------------------------

let root: Root | null = null;
export let container: HTMLDivElement;

export function mount(element: ReactElement) {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => root!.render(element));
}

export function unmount() {
  if (root) act(() => root!.unmount());
  root = null;
  container?.remove();
}

/** Lets pending promises and effects settle. */
export async function settle(times = 6) {
  for (let i = 0; i < times; i++) {
    await act(async () => {
      await Promise.resolve();
      await new Promise((r) => setTimeout(r, 0));
    });
  }
}

export const text = () => container.textContent ?? '';

export function button(label: string | RegExp): HTMLButtonElement | undefined {
  return [...container.querySelectorAll('button')].find((b) =>
    typeof label === 'string' ? b.textContent === label : label.test(b.textContent ?? ''),
  );
}

export function click(label: string | RegExp) {
  const b = button(label);
  expect(b, `button ${String(label)}`).toBeDefined();
  act(() => b!.click());
}

export function field<T extends HTMLElement = HTMLInputElement>(selector: string): T {
  const el = container.querySelector(selector) as T | null;
  expect(el, selector).not.toBeNull();
  return el!;
}

/** Types into a controlled input or textarea. */
export function type(selector: string, value: string) {
  const el = field<HTMLInputElement | HTMLTextAreaElement>(selector);
  const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
  act(() => {
    Object.getOwnPropertyDescriptor(proto, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

/** Leaves an input (blur), as the phone does when the keyboard closes. */
export function blur(selector: string) {
  const el = field(selector);
  act(() => {
    el.dispatchEvent(new FocusEvent('focusout', { bubbles: true }));
  });
}

/** Chooses [file] in a file input. */
export function choose(selector: string, file: File) {
  const el = field(selector);
  Object.defineProperty(el, 'files', { value: [file], configurable: true });
  act(() => {
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

export const png = (name = 'me.png') => new File([new Uint8Array([137, 80, 78, 71, 1, 2, 3])], name, { type: 'image/png' });

export { createElement };

// ---- fixtures --------------------------------------------------------------

export const baseConfig: ImageConfig = {
  backend: 'comfyui',
  isConfigured: true,
  size: '1024x1024',
  style: 'photorealistic',
  model: '',
  editModel: '',
  negativePrompt: '',
  steps: 8,
  cfgScale: 1,
  sampler: 'euler',
  scheduler: 'simple',
  drawThingsSampler: 16,
  drawThingsSamplers: [
    { label: 'DDIM Trailing', value: 16 },
    { label: 'Euler a', value: 1 },
  ],
  loras: [],
  localUrl: 'http://127.0.0.1:7860',
  comfyUrl: 'http://127.0.0.1:8188',
  promptReview: false,
  drawThingsHost: '127.0.0.1',
  drawThingsPort: 7859,
  remoteApiUrl: 'https://example.test',
  hasApiKey: false,
  comfyCreateWorkflowId: 'z_image_turbo',
  comfyCreateModelChoices: { 'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors' },
  comfyEditWorkflowId: 'qwen_image_edit',
  comfyEditModelChoices: {},
};

export const readyFacts = {
  ready: true,
  kind: 'ready',
  primary: 'z_image_turbo_bf16.safetensors',
  loraFamily: 'zImage',
  reachable: true,
  diffusionCount: 3,
  loraCount: 2,
  mode: 'create',
  workflowId: 'z_image_turbo',
  slots: [
    { token: '%MODEL_DIFFUSION%', label: 'Diffusion model', file: 'z_image_turbo_bf16.safetensors' },
    { token: '%MODEL_CLIP%', label: 'Text encoder', file: 'qwen_3_4b.safetensors' },
    { token: '%MODEL_VAE%', label: 'VAE', file: '' },
  ],
};

/** The words in the open sheet, without the desk behind it. */
export const sheetText = () => container.querySelector('[role="dialog"]')?.textContent ?? '';

/** Chooses [value] in a select. */
export function pickOption(selector: string, value: string) {
  const el = field<HTMLSelectElement>(selector);
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')!.set!.call(el, value);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

/** Waits until [ready] is true, for at most [ms]. */
export async function until(ready: () => boolean, ms = 2000) {
  const end = Date.now() + ms;
  while (!ready() && Date.now() < end) await settle(1);
  expect(ready()).toBe(true);
}
