// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { StudioDesk, type StudioDeskProps } from './StudioDesk';

const readyUrls: string[] = [];
vi.mock('../../api/client', () => ({
  api: {
    get: vi.fn((url: string) => {
      readyUrls.push(url);
      if (url.includes('/api/image/studio/ready')) {
        return Promise.resolve({ ready: false });
      }
      return Promise.reject(new Error('offline'));
    }),
    post: vi.fn().mockResolvedValue({}),
  },
}));

let container: HTMLDivElement;
let root: Root;

afterEach(() => {
  act(() => root?.unmount());
  container?.remove();
});

const base: StudioDeskProps = {
  backend: 'remote',
  model: '',
  size: '1024x1024',
  steps: 20,
  sampler: 'euler',
  workflowId: 'sd',
  comfyUrl: 'http://127.0.0.1:8188',
  localUrl: 'http://127.0.0.1:7860',
  drawThingsHost: '127.0.0.1',
  remoteUrl: '',
  onSave: () => {},
};

function render(extra: Partial<StudioDeskProps> = {}) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(createElement(StudioDesk, { ...base, ...extra }));
  });
}

describe('StudioDesk', () => {
  it('stays off the phone page until it replaces the working form', () => {
    const page = readFileSync('src/components/models/ImageGen.tsx', 'utf8');
    expect(page).toContain('<StudioDesk');
    expect(page).toContain("'sd'");
    expect(page).not.toContain('<ComfyCreateFields');
  });

  it('keeps Generate off until a model is saved', () => {
    const saved: Record<string, unknown>[] = [];
    render({ onSave: (patch) => saved.push(patch) });
    const text = container.textContent ?? '';
    expect(text).toContain('Model search');
    expect(text).toContain('CivitAI sign-in');
    const generate = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Generate');
    expect(generate?.hasAttribute('disabled')).toBe(true);
    const search = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Model search');
    act(() => search?.click());
    const box = container.querySelector('input[aria-label="Search"]') as HTMLInputElement;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    act(() => {
      setter?.call(box, 'portrait.safetensors');
      box.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const use = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Use portrait.safetensors');
    act(() => use?.click());
    expect(saved.some((patch) => patch.model === 'portrait.safetensors')).toBe(true);
  });

  it('keeps page generate on create readiness when the desk is in edit', async () => {
    readyUrls.length = 0;
    render();
    await act(async () => { await Promise.resolve(); });
    const edit = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Edit');
    act(() => edit?.click());
    await act(async () => { await Promise.resolve(); });
    const asked = readyUrls.filter((url) => url.includes('/api/image/studio/ready'));
    expect(asked.length).toBeGreaterThan(0);
    expect(asked.every((url) => url.includes('mode=create'))).toBe(true);
  });

  it('asks about readiness only after the save finishes', async () => {
    readyUrls.length = 0;
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => { release = resolve; });
    render({ onSave: () => gate });
    await act(async () => { await Promise.resolve(); });
    const before = readyUrls.filter((url) => url.includes('/api/image/studio/ready')).length;
    const search = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Model search');
    act(() => search?.click());
    const box = container.querySelector('input[aria-label="Search"]') as HTMLInputElement;
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    act(() => {
      setter?.call(box, 'portrait.safetensors');
      box.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const use = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Use portrait.safetensors');
    act(() => use?.click());
    await act(async () => { await Promise.resolve(); });
    const during = readyUrls.filter((url) => url.includes('/api/image/studio/ready')).length;
    expect(during).toBe(before);
    release();
    await act(async () => { await gate; await Promise.resolve(); });
    const after = readyUrls.filter((url) => url.includes('/api/image/studio/ready')).length;
    expect(after).toBeGreaterThan(during);
  });
});
