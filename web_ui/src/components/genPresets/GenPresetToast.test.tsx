// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The model-switch toast (issue 686): a notice that arrives while the page
// is open shows with Undo; one left from before the page opened does not;
// Undo and ✕ answer that notice by its id. The model picker beside a model
// links that model, and None unlinks it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GenPresetToast } from './GenPresetToast';
import { ModelPresetSelect } from './ModelPresetSelect';
import { normalizeGenPresets, type GenPresets } from './genPresets';

const BASE = normalizeGenPresets({
  presets: [{ name: 'Precise', values: { temperature: 0.4 } }],
  model: { key: 'remote:https://x/v1|qwen3', label: 'qwen3' },
  links: { 'local:other.gguf': 'Precise' },
  live: { temperature: 0.4 },
});
const withNotice = (id: number): GenPresets => ({
  ...BASE,
  notice: { id, message: `qwen3 writes with “Precise”. (#${id})` },
});

let container: HTMLDivElement;
let root: Root;
let calls: [string, Record<string, unknown> | undefined][];
const act$ = vi.fn(async (action: string, body?: Record<string, unknown>) => {
  calls.push([action, body]);
  return { ...BASE, undone: action === 'undo' };
});

const render = async (el: ReturnType<typeof createElement>) => {
  await act(async () => {
    root.render(el);
  });
};
const toast = () => container.querySelector('[data-testid="gen-preset-toast"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  calls = [];
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the model-switch toast', () => {
  it('shows only a notice that arrives while open, and Undo answers it', async () => {
    const undone: GenPresets[] = [];
    const el = (data: GenPresets | null) =>
      createElement(GenPresetToast, {
        data,
        act: act$,
        extra: "This chat's own changes (2) still apply.",
        onUndone: (n: GenPresets) => undone.push(n),
      });
    await render(el(withNotice(3)));
    expect(toast(), 'a notice from before the page opened').toBeNull();

    await render(el(withNotice(4)));
    expect(toast()!.textContent).toContain(
      "qwen3 writes with “Precise”. (#4) This chat's own changes (2) still apply.",
    );
    await act(async () => {
      [...toast()!.querySelectorAll('button')].find((b) => b.textContent === 'Undo')!.click();
    });
    expect(calls).toEqual([['undo', { id: 4 }]]);
    expect(undone).toHaveLength(1);

    await act(async () => {
      (toast()!.querySelector('button[aria-label="Dismiss"]') as HTMLButtonElement).click();
    });
    expect(calls[1]).toEqual(['dismiss', { id: 4 }]);
  });

  it('a page that first saw no notice shows the first one', async () => {
    const el = (data: GenPresets | null) => createElement(GenPresetToast, { data, act: act$ });
    await render(el(null));
    await render(el(BASE));
    expect(toast()).toBeNull();
    await render(el(withNotice(1)));
    expect(toast()).not.toBeNull();
  });
});

describe('the model card preset picker', () => {
  it('links the model it sits beside, by key, and None unlinks it', async () => {
    const linked: GenPresets[] = [];
    await render(
      createElement(ModelPresetSelect, {
        data: BASE,
        act: act$,
        modelKey: 'local:other.gguf',
        onLinked: (n: GenPresets) => linked.push(n),
      }),
    );
    const select = container.querySelector('select')!;
    expect(select.value).toBe('Precise');
    expect(container.textContent).toContain('Loads every time this model is picked.');
    await act(async () => {
      select.value = '';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(calls).toEqual([['link', { name: null, modelKey: 'local:other.gguf' }]]);
    expect(linked, 'not the chat model: nothing loaded now').toEqual([]);
  });

  it('on the chat model, says it loads now and hands back what loaded', async () => {
    const linked: GenPresets[] = [];
    await render(
      createElement(ModelPresetSelect, {
        data: BASE,
        act: act$,
        modelKey: 'remote:https://x/v1|qwen3',
        onLinked: (n: GenPresets) => linked.push(n),
      }),
    );
    const select = container.querySelector('select')!;
    expect(select.value).toBe('');
    expect(container.textContent).toContain('Loads now and every time this model is picked.');
    await act(async () => {
      select.value = 'Precise';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(calls).toEqual([['link', { name: 'Precise', modelKey: 'remote:https://x/v1|qwen3' }]]);
    expect(linked).toHaveLength(1);
  });

  it('shows nothing without a model', async () => {
    await render(createElement(ModelPresetSelect, { data: BASE, act: act$, modelKey: null }));
    expect(container.querySelector('select')).toBeNull();
  });
});
