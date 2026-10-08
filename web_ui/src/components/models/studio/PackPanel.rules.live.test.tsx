// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it } from 'vitest';
import { PackPanel } from './PackPanel';
import type { PromptRules } from './packApi';

const base = process.env.FPAI_RULES_TEST_URL;
const mode = process.env.FPAI_RULES_TEST_MODE;
const originalFetch = globalThis.fetch;
let root: Root;
let host: HTMLDivElement;
const posted: { path: string; body: Record<string, unknown> }[] = [];
const completed: { path: string; status: number }[] = [];
Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });
Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
  configurable: true, value() { this.setAttribute('open', ''); },
});
Object.defineProperty(HTMLDialogElement.prototype, 'close', {
  configurable: true, value() { this.removeAttribute('open'); },
});
beforeEach(() => {
  posted.length = 0;
  completed.length = 0;
  globalThis.fetch = async (input, init) => {
    const path = String(input);
    if (init?.method === 'POST') posted.push({ path, body: JSON.parse(String(init.body)) as Record<string, unknown> });
    const response = await originalFetch(new URL(path, base), init);
    if (init?.method === 'POST') completed.push({ path, status: response.status });
    return response;
  };
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
});
afterEach(() => {
  if (root) act(() => root.unmount());
  host?.remove();
  globalThis.fetch = originalFetch;
});
async function until(check: () => boolean) {
  for (let i = 0; i < 900 && !check(); i++) {
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
  }
  expect(check()).toBe(true);
}
const button = (text: string) => [...host.querySelectorAll('button')].find((b) => b.textContent === text)!;
const click = (text: string) => act(() => button(text).click());
const rules = (prefix: string): PromptRules => ({ prefix, suffix: '', replacements: [] });
async function mount() {
  act(() => root.render(createElement(PackPanel, {
    prompt: 'an illustrated portrait', picture: { kind: 'file', name: 'portrait.png',
      dataUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=' },
  })));
  await until(() => host.querySelectorAll('option').length > 0);
}
async function editPrefix(value: string) {
  const field = host.querySelector<HTMLTextAreaElement>('[aria-label="Prefix"]')!;
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!.call(field, value);
    field.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await until(() => !button('Use for this pack').disabled);
}
it.skipIf(!base || mode !== 'lifecycle')('local defaults cancel and next-pack scope through actual API', async () => {
  await mount();
  click('Prompt rules...');
  await until(() => !!host.querySelector('dialog'));
  await editPrefix('saved elsewhere');
  click('Save as global defaults');
  await until(() => host.textContent!.includes('Global defaults saved.'));
  click('Cancel');
  click('Start pack');
  await until(() => posted.some((p) => p.path === '/api/image/expression-pack'));
  const starts = () => posted.filter((p) => p.path === '/api/image/expression-pack');
  expect((starts()[0].body.promptRules as PromptRules).prefix).toBe('original');
  await until(() => !!host.querySelector('[data-region="pack-status"]') && !button('Start pack').disabled);
  click('Edit pack prompt rules...');
  await until(() => !!host.querySelector('dialog'));
  await editPrefix('iteration wording');
  click('Use for this pack');
  await until(() => !host.querySelector('dialog'));
  expect(posted.some((p) => p.path.endsWith('/rules') && (p.body.promptRules as PromptRules).prefix === 'iteration wording')).toBe(true);
  click('Prompt rules...');
  await until(() => !!host.querySelector('dialog'));
  await editPrefix('local next pack');
  click('Use for this pack');
  await until(() => !host.querySelector('dialog'));
  click('Start pack');
  await until(() => starts().length === 2 && !button('Start pack').disabled);
  expect((starts()[1].body.promptRules as PromptRules).prefix).toBe('local next pack');
  await originalFetch(new URL('/api/image/expression-pack/settings', base), {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ promptRules: rules('fresh global') }),
  });
  click('Start pack');
  await until(() => starts().length === 3 && !button('Start pack').disabled);
  expect(starts()[2].body).not.toHaveProperty('promptRules');
  const latest = await (await originalFetch(new URL('/api/image/expression-pack', base))).json() as { promptRules: PromptRules };
  expect(latest.promptRules.prefix).toBe('fresh global');
}, 90_000);
it.skipIf(!base || mode !== 'desktop')('desktop-owned pack cannot be edited on the phone', async () => {
  await mount();
  await until(() => host.textContent!.includes('Started on the computer.'));
  expect(button('Edit pack prompt rules...')).toBeUndefined();
  expect(button('Generate remaining')).toBeUndefined();
});
it.skipIf(!base || mode !== 'iteration')('resume and reroll buttons reach their production routes', async () => {
  await mount();
  await until(() => !!button('Generate remaining'));
  click('Generate remaining');
  await until(() => completed.some((p) => p.path.endsWith('/resume')) && !button('Start pack').disabled);
  expect(completed.find((p) => p.path.endsWith('/resume'))!.status).toBe(200);
  click('Reroll joy');
  await until(() => completed.some((p) => p.path.endsWith('/reroll')) && !button('Start pack').disabled);
  expect(completed.find((p) => p.path.endsWith('/reroll'))!.status).toBe(200);
  expect(posted.find((p) => p.path.endsWith('/reroll'))!.body).toEqual({ emotion: 'joy' });
}, 90_000);
