// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Output step's Save as template and the template dialogs: the Started
// from pill and caption; the Save dialog prefilled from the template the
// form came from, with the replace caption or the name problem, a confirm
// that a problem disables, one PUT however fast the taps, and a body that
// carries the form and `basedOn`; the relay's refusal shown in the dialog;
// the phone's bottom sheet against the wide dialog; Rename's taken name from
// the relay; Escape. The relay itself is stood in for; the browser journey
// saves through the real one.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DEFAULT_FORM, type ChargenForm } from './chargenForm';
import { formToTemplate } from './templateForm';
import { REPLACES_CAPTION, templateSlug, type CreatorTemplate, type TemplateStart } from './templatesApi';

const relay = vi.hoisted(() => ({
  calls: [] as { method: string; path: string; body?: unknown }[],
  /** The next answer; a function throws it, a promise holds it. */
  next: null as null | (() => unknown),
}));
vi.mock('../../api/client', () => {
  class ApiError extends Error {
    status: number;
    payload: Record<string, unknown>;
    constructor(status: number, message: string, payload: Record<string, unknown> = {}) {
      super(message);
      this.status = status;
      this.payload = payload;
    }
  }
  const answer = async (method: string, path: string, body?: unknown) => {
    relay.calls.push({ method, path, body });
    const next = relay.next;
    relay.next = null;
    return next ? next() : {};
  };
  return {
    ApiError,
    api: {
      get: async () => ({}),
      put: (path: string, body: unknown) => answer('PUT', path, body),
      post: (path: string, body: unknown) => answer('POST', path, body),
      del: (path: string) => answer('DELETE', path),
    },
  };
});

const { ApiError } = await import('../../api/client');
const { TemplateSaveBar } = await import('./TemplateSaveBar');
const { RenameTemplateSheet, DeleteTemplateSheet } = await import('./TemplateSheets');

const tpl = (name: string, over: Partial<CreatorTemplate> = {}): CreatorTemplate => ({
  slug: templateSlug(name), name, savedAt: null, builtIn: false, broken: false, problem: null,
  summary: { mode: 'quick', perspective: 'first', tense: 'present', lore: false, nsfw: false, blurb: '' },
  form: {}, ...over,
});
const HARBOR = tpl('Harbor town, slow burn', { savedAt: '2026-10-04T12:00:00Z' });
const TSUNDERE = tpl('Tsundere', { builtIn: true });
const LIST = [HARBOR, tpl('Modern 18+ quick'), TSUNDERE, tpl('Kuudere', { builtIn: true })];
const FORM: ChargenForm = { ...DEFAULT_FORM, name: 'Maren', mode: 'guided', vision: 'A lighthouse keeper.', narrativePerspective: 'third' };
const FROM_HARBOR: TemplateStart = { slug: HARBOR.slug, name: HARBOR.name, builtIn: false };

let container: HTMLDivElement;
let root: Root;
const onSaved = vi.fn();

async function act$(fn: () => void) {
  await act(async () => {
    fn();
    await new Promise((r) => setTimeout(r, 0));
  });
}
async function renderBar(width: number, startedFrom: TemplateStart | null) {
  (window as { innerWidth: number }).innerWidth = width;
  await act$(() => root.render(createElement(TemplateSaveBar, { form: FORM, templates: LIST, startedFrom, onSaved })));
}
const dialog = () => container.querySelector<HTMLElement>('[role="dialog"]');
const field = () => dialog()!.querySelector('input')!;
const button = (label: string, scope: ParentNode = container) => {
  const b = Array.from(scope.querySelectorAll('button')).find((x) => x.textContent?.trim() === label);
  if (!b) throw new Error(`no button ${label}`);
  return b as HTMLButtonElement;
};
const confirmButton = () => button('Save template', dialog()!);
function type(value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(field(), value);
  act(() => {
    field().dispatchEvent(new Event('input', { bubbles: true }));
  });
}
const openSave = () => act$(() => button('Save as template').click());

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  relay.calls.length = 0;
  relay.next = null;
  onSaved.mockReset();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Save as template', () => {
  it('shows no pill on a blank form; the dialog starts empty and quiet', async () => {
    await renderBar(390, null);
    expect(container.textContent).not.toContain('Started from');
    await openSave();
    expect(dialog()!.querySelector('h2')!.textContent).toBe('Save as a template');
    expect(dialog()!.textContent).toContain(
      "Keeps every box on this form the way it is now, in every step. Not the character's name. It shows on the desktop too.",
    );
    expect(dialog()!.textContent).toContain('TEMPLATE NAME');
    expect(field().value).toBe('');
    expect(dialog()!.querySelector('.cg-sheet-problem')).toBeNull();
    expect(confirmButton().disabled).toBe(false);

    // Confirming an empty name says why and sends nothing.
    await act$(() => confirmButton().click());
    expect(dialog()!.querySelector('.cg-sheet-problem')!.textContent).toBe('Give the template a name.');
    expect(confirmButton().disabled).toBe(true);
    expect(relay.calls).toEqual([]);
  });

  it('started from a template: the pill, the prefilled name, the replace caption, and a PUT with basedOn', async () => {
    await renderBar(390, FROM_HARBOR);
    expect(container.querySelector('.cg-tpl-from')!.textContent).toBe('Started from: Harbor town, slow burn');
    expect(container.textContent).toContain('Changes stay on this form until you save them to the template.');
    await openSave();
    expect(field().value).toBe('Harbor town, slow burn');
    expect(dialog()!.querySelector('.cg-sheet-caption')!.textContent).toBe(REPLACES_CAPTION);

    relay.next = () => ({ template: { ...HARBOR, savedAt: '2026-10-14T12:00:00Z' }, replaced: true });
    await act$(() => {
      confirmButton().click();
      confirmButton().click();
    });
    expect(relay.calls).toEqual([
      {
        method: 'PUT',
        path: `/api/chargen/templates/${HARBOR.slug}`,
        body: { name: 'Harbor town, slow burn', form: formToTemplate(FORM), basedOn: HARBOR.slug },
      },
    ]);
    expect((relay.calls[0].body as { form: object }).form).not.toHaveProperty('name');
    expect(onSaved).toHaveBeenCalledWith(FROM_HARBOR);
    expect(dialog()).toBeNull();
  });

  it('a new name has no caption; a built-in\'s name is refused', async () => {
    await renderBar(1280, FROM_HARBOR);
    await openSave();
    type('Harbor town, winter');
    expect(dialog()!.querySelector('.cg-sheet-caption')).toBeNull();
    expect(dialog()!.querySelector('.cg-sheet-problem')).toBeNull();
    type('tsundere');
    expect(dialog()!.querySelector('.cg-sheet-problem')!.textContent).toBe(
      "Tsundere is a built-in template and can't be changed. Give yours another name.",
    );
    expect(confirmButton().disabled).toBe(true);
    type('Harbor town, winter');
    relay.next = () => ({ template: null, replaced: false });
    await act$(() => confirmButton().click());
    expect(relay.calls.map((c) => c.path)).toEqual(['/api/chargen/templates/harbor-town-winter']);
    expect(onSaved).toHaveBeenCalledWith({ slug: 'harbor-town-winter', name: 'Harbor town, winter', builtIn: false });
    // Grok, 2026-10-14: a new name has no stored file to merge over, so the
    // desktop-only keys survive only through basedOn.
    expect((relay.calls[0].body as { basedOn?: string }).basedOn).toBe(HARBOR.slug);
  });

  it('Save waits until the template list has arrived, so a built-in name cannot slip through', async () => {
    // Grok, 2026-10-14: with the list unknown the sheet knew no built-ins
    // and let "Tsundere" through with Save enabled.
    (window as { innerWidth: number }).innerWidth = 1280;
    await act$(() => root.render(createElement(TemplateSaveBar, { form: FORM, templates: null, startedFrom: null, onSaved })));
    expect(button('Save as template').disabled).toBe(true);
    await act$(() => root.render(createElement(TemplateSaveBar, { form: FORM, templates: LIST, startedFrom: null, onSaved })));
    expect(button('Save as template').disabled).toBe(false);
  });

  it('a refused save stays open with the relay\'s words', async () => {
    await renderBar(390, FROM_HARBOR);
    await openSave();
    relay.next = () => {
      throw new ApiError(400, 'The form could not be read.');
    };
    await act$(() => confirmButton().click());
    expect(dialog()!.textContent).toContain('The form could not be read.');
    expect(onSaved).not.toHaveBeenCalled();
    expect(confirmButton().disabled).toBe(false);
  });

  it('is a bottom sheet with a handle and the confirm first on the phone, a dialog wide', async () => {
    await renderBar(390, null);
    await openSave();
    expect(dialog()!.classList.contains('phone')).toBe(true);
    expect(dialog()!.querySelector('.cg-sheet-handle')).not.toBeNull();
    expect(Array.from(dialog()!.querySelectorAll('.cg-sheet-actions button')).map((b) => b.textContent)).toEqual([
      'Save template', 'Cancel',
    ]);
    await act$(() => button('Cancel', dialog()!).click());
    expect(dialog()).toBeNull();

    await renderBar(1280, null);
    await openSave();
    expect(dialog()!.classList.contains('phone')).toBe(false);
    expect(dialog()!.querySelector('.cg-sheet-handle')).toBeNull();
    expect(Array.from(dialog()!.querySelectorAll('.cg-sheet-actions button')).map((b) => b.textContent)).toEqual([
      'Cancel', 'Save template',
    ]);
    await act$(() => dialog()!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })));
    expect(dialog()).toBeNull();
  });
});

describe('Rename and Delete', () => {
  it('Rename shows the relay\'s taken answer', async () => {
    const onRenamed = vi.fn();
    (window as { innerWidth: number }).innerWidth = 390;
    await act$(() =>
      root.render(createElement(RenameTemplateSheet, { template: HARBOR, templates: LIST, onRenamed, onClose: () => {} })),
    );
    type('Harbor town, winter');
    relay.next = () => {
      throw new ApiError(409, 'taken', { reason: 'taken' });
    };
    await act$(() => button('Rename', dialog()!).click());
    expect(dialog()!.querySelector('.cg-sheet-problem')!.textContent).toBe('Another template already has this name.');
    expect(onRenamed).not.toHaveBeenCalled();
  });

  it('a failed delete says so and keeps the dialog', async () => {
    const onDeleted = vi.fn();
    await act$(() => root.render(createElement(DeleteTemplateSheet, { template: HARBOR, onDeleted, onClose: () => {} })));
    expect(dialog()!.classList.contains('danger')).toBe(true);
    relay.next = () => {
      throw new TypeError('Failed to fetch');
    };
    await act$(() => button('Delete', dialog()!).click());
    expect(dialog()!.textContent).toContain('The template could not be deleted. Check the connection, then try again.');
    expect(dialog()!.textContent).not.toContain('Failed to fetch');
    expect(onDeleted).not.toHaveBeenCalled();
  });
});
