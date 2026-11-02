// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Generation preset bar on the phone's Settings (issue 686, option B):
// the badge follows the sliders on screen; Save sends the values shown;
// Save as new names the preset in the page (no browser prompt); Delete asks
// in the page first; the link switch links the bar's preset to the chat
// model; and whatever the host now holds goes back to the page.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { GenPresetBar } from './GenPresetBar';
import { normalizeGenPresets, type GenPresets, type SamplerValues } from './genPresets';

const DATA: GenPresets = normalizeGenPresets({
  presets: [
    { name: 'Warm', values: { temperature: 1.1, minP: 0.05 } },
    { name: 'Precise', values: { temperature: 0.4 } },
  ],
  slot: 'Warm',
  state: 'saved',
  model: { key: 'local:cydonia.gguf', label: 'Cydonia-24B', local: true },
  linked: null,
  links: {},
  recommended: {
    values: { temperature: 0.8 },
    resetValues: { temperature: 0.8 },
    source: 'family',
    sourceWords: 'recommended for Mistral',
  },
  live: { temperature: 1.1, minP: 0.05 },
  notice: null,
});

let container: HTMLDivElement;
let root: Root;
let calls: [string, Record<string, unknown> | undefined][];
let adopted: SamplerValues[];
let answer: GenPresets;

const act$ = vi.fn(async (action: string, body?: Record<string, unknown>) => {
  calls.push([action, body]);
  return answer;
});

async function show(shown: SamplerValues, data: GenPresets = DATA) {
  await act(async () => {
    root.render(
      createElement(GenPresetBar, {
        data,
        error: '',
        act: act$,
        shown,
        onAdopt: (v: SamplerValues) => adopted.push(v),
      }),
    );
  });
}

const $ = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const button = (text: string) =>
  [...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === text) as
    | HTMLButtonElement
    | undefined;
const click = async (el: Element | undefined) => {
  await act(async () => {
    (el as HTMLElement).click();
  });
};

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  calls = [];
  adopted = [];
  answer = { ...DATA, live: { temperature: 0.4 } };
  act$.mockClear();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Generation preset bar', () => {
  it('badges the sliders on screen, and Save to sends them', async () => {
    await show({ temperature: 1.1, minP: 0.05 });
    expect($('gen-preset-badge')!.textContent).toBe('Saved');
    expect(button('Save to “Warm”')!.disabled).toBe(true);

    await show({ temperature: 0.9, minP: 0.05 });
    expect($('gen-preset-badge')!.textContent).toBe('Warm (edited)');
    await click(button('Save to “Warm”'));
    expect(calls).toEqual([['save', { name: 'Warm', values: { temperature: 0.9, minP: 0.05 } }]]);
    expect(adopted).toEqual([{ temperature: 0.4 }]);
  });

  it('names a new preset in the page, never with a browser prompt', async () => {
    const prompt = vi.spyOn(window, 'prompt');
    await show({ temperature: 0.9 });
    await click(button('Save as new…'));
    const input = container.querySelector<HTMLInputElement>('input[aria-label="New preset name"]')!;
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, ' Night ');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await click(button('Save'));
    expect(prompt).not.toHaveBeenCalled();
    expect(calls).toEqual([['save', { name: 'Night', values: { temperature: 0.9 } }]]);
    expect(container.querySelector('input[aria-label="New preset name"]')).toBeNull();
  });

  it('says a taken name is replaced', async () => {
    await show({ temperature: 0.9 });
    await click(button('Save as new…'));
    const input = container.querySelector<HTMLInputElement>('input[aria-label="New preset name"]')!;
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(input, 'Precise');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(button('Replace')).toBeDefined();
  });

  it('asks in the page before deleting, and Cancel deletes nothing', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    await show({ temperature: 1.1, minP: 0.05 });
    await click(container.querySelector('button[aria-label="Delete “Warm”"]')!);
    expect(container.textContent).toContain('Delete “Warm”?');
    await click(button('Cancel'));
    expect(calls).toEqual([]);
    await click(container.querySelector('button[aria-label="Delete “Warm”"]')!);
    await click(button('Delete'));
    expect(confirm).not.toHaveBeenCalled();
    expect(calls).toEqual([['delete', { name: 'Warm' }]]);
    expect(adopted).toEqual([]);
  });

  it('loads a picked preset and links the bar preset to the chat model', async () => {
    await show({ temperature: 1.1, minP: 0.05 });
    const select = container.querySelector<HTMLSelectElement>('select[aria-label="Generation preset"]')!;
    await act(async () => {
      select.value = 'Precise';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(calls).toEqual([['load', { name: 'Precise' }]]);
    expect(adopted).toEqual([{ temperature: 0.4 }]);

    expect(container.textContent).toContain(
      'Use this preset whenever Cydonia-24B is the chat model',
    );
    const link = container.querySelector<HTMLInputElement>('.gp-link input')!;
    expect(link.checked).toBe(false);
    await click(link);
    expect(calls[1]).toEqual(['link', { name: 'Warm' }]);

    await show({ temperature: 1.1, minP: 0.05 }, { ...DATA, linked: 'Warm' });
    expect(container.textContent).toContain('Linked to Cydonia-24B');
    await click(container.querySelector<HTMLInputElement>('.gp-link input')!);
    expect(calls[2]).toEqual(['link', { name: null }]);
  });

  it('cannot link without a chat model, and shows the recommended line', async () => {
    await show({ temperature: 1.1 }, { ...DATA, model: null });
    expect(container.querySelector<HTMLInputElement>('.gp-link input')!.disabled).toBe(true);
    expect(container.textContent).toContain('No chat model is chosen yet.');

    await show({ temperature: 1.1 });
    expect($('gen-preset-recommended')!.textContent).toBe(
      'Cydonia-24B: temp 0.8, recommended for Mistral.',
    );
    await click(button('Reset all to defaults'));
    expect(calls).toEqual([['reset-all', {}]]);
    expect(adopted).toEqual([{ temperature: 0.4 }]);
  });
});
