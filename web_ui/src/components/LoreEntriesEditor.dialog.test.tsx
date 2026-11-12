// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The character editor's lorebook edits an entry in a dialog, as the desktop
// does: Edit opens it, Cancel leaves the entry alone, Save applies it, and an
// Always Active entry hides the Sticky Depth and Chance sliders.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement, useState } from 'react';
import { afterEach, describe, expect, it } from 'vitest';
import { LoreEntriesEditor, type LoreEntry } from './LoreEntriesEditor';

let root: Root | null = null;
let host: HTMLDivElement | null = null;
let latest: LoreEntry[] = [];

function mount(initial: LoreEntry[]) {
  function Harness() {
    const [e, setE] = useState(initial);
    latest = e;
    return createElement(LoreEntriesEditor, {
      entries: e,
      onChange: setE,
      editorChrome: { onFromCharacter: () => {}, fileName: 'x.json' },
    });
  }
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  act(() => root!.render(createElement(Harness)));
}

const click = (el: Element | null | undefined) => act(() => (el as HTMLElement).click());
const byText = (t: string) =>
  Array.from(document.querySelectorAll('button')).find((b) => b.textContent?.trim() === t);
const set = (el: HTMLInputElement, v: string) =>
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });

afterEach(() => {
  act(() => root?.unmount());
  host?.remove();
});

const entry: LoreEntry = {
  name: 'Harbor',
  key: 'harbor, pier',
  content: 'Gulls.',
  enabled: true,
  constant: false,
  stickyDepth: 3,
};

describe('lore entry dialog', () => {
  it('Edit opens a dialog; Cancel keeps the entry, Save applies the change', () => {
    mount([entry]);
    expect(document.querySelector('[data-testid="lore-entry-dialog"]')).toBeNull();
    click(document.querySelector('[title="Edit entry"]'));
    const dlg = () => document.querySelector('[data-testid="lore-entry-dialog"]')!;
    expect(dlg().textContent).toContain('Edit Lorebook Entry');
    set(dlg().querySelector('input[placeholder="Name (optional)"]')!, 'Dock');
    click(byText('Cancel'));
    expect(latest[0].name).toBe('Harbor');
    click(document.querySelector('[title="Edit entry"]'));
    set(dlg().querySelector('input[placeholder="Name (optional)"]')!, 'Dock');
    click(byText('Save'));
    expect(latest[0].name).toBe('Dock');
  });

  it('Add Entry opens an empty dialog and Add appends it', () => {
    mount([]);
    click(byText('Add Entry'));
    expect(document.body.textContent).toContain('Add Lorebook Entry');
    click(byText('Add'));
    expect(latest).toHaveLength(1);
  });

  it('Always Active hides the Sticky Depth and Chance sliders', () => {
    mount([{ ...entry, constant: true }]);
    click(document.querySelector('[title="Edit entry"]'));
    expect(document.querySelectorAll('input[type="range"]')).toHaveLength(0);
    mount([entry]);
    click(document.querySelectorAll('[title="Edit entry"]')[1]);
    expect(document.querySelectorAll('input[type="range"]').length).toBe(2);
  });
});
