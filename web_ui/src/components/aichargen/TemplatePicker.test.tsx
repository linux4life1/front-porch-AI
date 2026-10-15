// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Mode step's template picker on a list shaped like the relay's (yours
// newest first, then the built-ins with Tsundere and Kuudere first): the
// tile order, the phone and wide lines, the Built in pill without a menu,
// the selected tile, the ⋯ menu's Load, Rename and Delete (a broken file
// offers only Delete), the built-ins picker, and the load error; and on the
// creator page, Load filling the form (the typed name kept) with the
// Started from pill on Output until the character is saved. The relay calls
// go to a stand-in client; the round trip against the real relay is the
// browser journey.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ARCHETYPES } from './chargenForm';
import { templateSlug, type CreatorTemplate, type TemplateSummary } from './templatesApi';

const calls = vi.hoisted(() => [] as { method: string; path: string; body?: unknown }[]);
/** What GET /api/chargen/templates answers on the page (set per test). */
const relayList = vi.hoisted(() => ({ templates: [] as unknown[] }));
const sockets = vi.hoisted(() => [] as ((e: { event: string; id?: number }) => void)[]);
vi.mock('../../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: (e: { event: string; id?: number }) => void) {
      sockets.push(cb);
    }
    connect() {}
    close() {}
  },
}));
vi.mock('../../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path === '/api/chargen/templates') return relayList;
      if (path === '/api/chargen/status') return { available: true };
      if (path.startsWith('/api/chargen/interview')) {
        return { pronouns: { subject: 'they', possessive: 'their' }, rows: [{ key: 'voice', condition: null, text: 'How do they talk?' }] };
      }
      return {};
    },
    post: async (path: string, body: unknown) => {
      calls.push({ method: 'POST', path, body });
      const name = (body as { name: string }).name;
      return { template: { slug: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name } };
    },
    del: async (path: string) => {
      calls.push({ method: 'DELETE', path });
      return { deleted: true };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { TemplatePicker } = await import('./TemplatePicker');
const { CreateAiCharacterPage } = await import('../../pages/CreateAiCharacterPage');

const summary = (over: Partial<TemplateSummary> = {}): TemplateSummary => ({
  mode: 'quick', perspective: 'first', tense: 'present', lore: false, nsfw: false, blurb: '', ...over,
});
const tpl = (over: Partial<CreatorTemplate> & { name: string }): CreatorTemplate => ({
  slug: templateSlug(over.name), savedAt: null, builtIn: false, broken: false, problem: null,
  summary: summary(), form: {}, ...over,
});

/** The archetypes as the relay lists them: the two featured, then the rest. */
const BUILT_INS = ['Tsundere', 'Kuudere', ...Object.keys(ARCHETYPES).filter((n) => n !== 'Tsundere' && n !== 'Kuudere')]
  .map((name) => tpl({
    name, builtIn: true,
    summary: summary({ mode: 'automated', blurb: ARCHETYPES[name].keywords }),
    form: { mode: 'automated', automatedConcept: ARCHETYPES[name].concept },
  }));
const HARBOR = tpl({
  name: 'Harbor town, slow burn', savedAt: '2026-10-04T12:00:00Z',
  summary: summary({ mode: 'guided', perspective: 'third', tense: 'past', lore: true, nsfw: true }),
});
const MODERN = tpl({ name: 'Modern 18+ quick', savedAt: '2025-12-25T12:00:00Z', summary: summary({ nsfw: true }) });
const BROKEN = tpl({ name: 'old-file', broken: true, problem: 'not JSON' });
const LIST = [HARBOR, MODERN, BROKEN, ...BUILT_INS];

let container: HTMLDivElement;
let root: Root;
const onLoad = vi.fn();
const onRenamed = vi.fn();
const onDeleted = vi.fn();
const onRetry = vi.fn();

async function render(width: number, over: { templates?: CreatorTemplate[] | null; error?: string; selected?: string | null } = {}) {
  (window as { innerWidth: number }).innerWidth = width;
  await act(async () => {
    root.render(
      createElement(TemplatePicker, {
        templates: over.templates === undefined ? LIST : over.templates,
        error: over.error ?? '',
        onRetry,
        selected: over.selected ?? null,
        onLoad,
        onRenamed,
        onDeleted,
      }),
    );
  });
}

const tiles = () => Array.from(container.querySelectorAll<HTMLElement>('[data-testid="template-tile"]'));
const tileNamed = (name: string) => tiles().find((t) => t.textContent?.startsWith(name))!;
const buttons = (scope: ParentNode = container) => Array.from(scope.querySelectorAll('button'));
const button = (name: string | RegExp, scope: ParentNode = container) => {
  const b = buttons(scope).find((x) => {
    const label = x.getAttribute('aria-label') ?? x.textContent ?? '';
    return typeof name === 'string' ? label === name : name.test(label);
  });
  if (!b) throw new Error(`no button ${name}`);
  return b as HTMLButtonElement;
};
const dialog = () => container.querySelector<HTMLElement>('[role="dialog"]');
async function click(b: HTMLElement) {
  await act(async () => {
    b.click();
  });
}
async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}
function type(el: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, value);
  act(() => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-14T12:00:00Z'));
  calls.length = 0;
  for (const f of [onLoad, onRenamed, onDeleted, onRetry]) f.mockReset();
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('TemplatePicker', () => {
  it('shows yours in the relay\'s order, then Tsundere and Kuudere, then the tile for all fifteen (phone)', async () => {
    await render(390);
    expect(tiles().map((t) => t.querySelector('.cg-tpl-name, .cg-tpl-all-btn')!.textContent)).toEqual([
      'Harbor town, slow burn', 'Modern 18+ quick', 'old-file', 'Tsundere', 'Kuudere', 'All 15 built in',
    ]);
    expect(tileNamed('Harbor').textContent).toContain('Guided · lore on · 18+');
    expect(tileNamed('Harbor').textContent).toContain('Saved 4 Oct');
    expect(tileNamed('Modern').textContent).toContain('Saved 25 Dec 2025');
    const tsundere = tileNamed('Tsundere');
    expect(tsundere.textContent).toContain('Automated · sharp-tongued');
    expect(tsundere.textContent).not.toContain('secretly caring');
    expect(tsundere.querySelector('.cg-tpl-pill')!.textContent).toBe('Built in');
    expect(tsundere.textContent).not.toContain('Saved');
    expect(buttons().some((b) => b.getAttribute('aria-label') === 'More for Tsundere')).toBe(false);
    expect(container.textContent).not.toContain('Every box filled');
    expect(container.textContent).not.toContain('and the rest');
  });

  it('wide: the subtitle, the voice in your lines, two keywords, and who the rest are', async () => {
    await render(1280);
    expect(container.textContent).toContain('Every box filled the way you saved it. Pick one, or choose a mode below to start blank.');
    expect(tileNamed('Harbor').textContent).toContain('Guided · 3rd person, past · lore on · 18+');
    expect(tileNamed('Tsundere').textContent).toContain('Automated · sharp-tongued, secretly caring');
    expect(tileNamed('All 15').textContent).toContain('Yandere, Femme Fatale, Dark Lord and the rest');
  });

  it('marks the tile the form was loaded from', async () => {
    await render(390, { selected: HARBOR.slug });
    expect(tiles().filter((t) => t.classList.contains('on')).map((t) => t.textContent?.slice(0, 6))).toEqual(['Harbor']);
  });

  it('loads a tile by its name, or by Load in its menu', async () => {
    await render(390);
    await click(button('Kuudere'));
    expect(onLoad).toHaveBeenLastCalledWith(BUILT_INS[1]);
    await click(button('More for Harbor town, slow burn'));
    const menu = container.querySelector('[role="menu"]')!;
    expect(buttons(menu).map((b) => [b.textContent, b.classList.contains('danger')])).toEqual([
      ['Load', false], ['Rename', false], ['Delete', true],
    ]);
    await click(button('Load', menu));
    expect(onLoad).toHaveBeenLastCalledWith(HARBOR);
    expect(container.querySelector('[role="menu"]')).toBeNull();
  });

  it('a file that cannot be read says so and offers only Delete', async () => {
    await render(390);
    const broken = tileNamed('old-file');
    expect(broken.textContent).toContain("This file can't be read");
    expect(buttons(broken).map((b) => b.getAttribute('aria-label') ?? b.textContent)).toEqual(['More for old-file']);
    await click(button('More for old-file'));
    expect(buttons(container.querySelector('[role="menu"]')!).map((b) => b.textContent)).toEqual(['Delete']);
  });

  it('Rename renames through the relay and reports the new name', async () => {
    await render(390);
    await click(button('More for Modern 18+ quick'));
    await click(button('Rename', container.querySelector('[role="menu"]')!));
    expect(dialog()!.textContent).toContain('Rename template');
    const field = dialog()!.querySelector('input')!;
    expect(field.value).toBe('Modern 18+ quick');
    type(field, 'Harbor town, slow burn');
    expect(dialog()!.textContent).toContain('Another template already has this name.');
    expect(button('Rename', dialog()!).disabled).toBe(true);
    type(field, 'Modern, after dark');
    await click(button('Rename', dialog()!));
    await settle();
    expect(calls).toEqual([{ method: 'POST', path: `/api/chargen/templates/${MODERN.slug}/rename`, body: { name: 'Modern, after dark' } }]);
    expect(onRenamed).toHaveBeenCalledWith(MODERN.slug, { slug: 'modern-after-dark', name: 'Modern, after dark', builtIn: false });
    expect(dialog()).toBeNull();
  });

  it('Delete asks first, then deletes through the relay', async () => {
    await render(390);
    await click(button('More for Harbor town, slow burn'));
    await click(button('Delete', container.querySelector('[role="menu"]')!));
    expect(dialog()!.textContent).toContain('Delete this template?');
    expect(calls).toEqual([]);
    await click(button('Cancel', dialog()!));
    expect(dialog()).toBeNull();
    expect(onDeleted).not.toHaveBeenCalled();

    await click(button('More for Harbor town, slow burn'));
    await click(button('Delete', container.querySelector('[role="menu"]')!));
    await click(button('Delete', dialog()!));
    await settle();
    expect(calls).toEqual([{ method: 'DELETE', path: `/api/chargen/templates/${HARBOR.slug}` }]);
    expect(onDeleted).toHaveBeenCalledWith(HARBOR.slug);
    expect(dialog()).toBeNull();
  });

  it('All 15 built in opens the fifteen, and one loads', async () => {
    await render(1280);
    await click(button(/^All 15 built in/));
    expect(dialog()!.querySelector('h2')!.textContent).toBe('Built-in templates');
    const rows = Array.from(dialog()!.querySelectorAll('.cg-sheet-row-name')).map((r) => r.textContent);
    expect(rows).toEqual(BUILT_INS.map((t) => t.name));
    await click(button(/^Yandere/, dialog()!));
    expect(onLoad).toHaveBeenLastCalledWith(BUILT_INS[2]);
    expect(dialog()).toBeNull();
  });

  it('says when the list could not be loaded, and tries again', async () => {
    await render(390, { templates: null });
    expect(container.textContent).toContain('Loading templates…');
    await render(390, { templates: null, error: 'The templates could not be loaded. Check the connection, then try again.' });
    expect(container.textContent).toContain('The templates could not be loaded.');
    expect(container.textContent).not.toContain('Loading templates…');
    await click(button('Try again'));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });
});

describe('on the creator page', () => {
  const HARBOR_FORM = { ...HARBOR, form: { mode: 'guided', guidedVision: 'A lighthouse keeper.', narrativePerspective: 'third' } };

  async function openPage() {
    (window as { innerWidth: number }).innerWidth = 390;
    relayList.templates = [HARBOR_FORM, ...BUILT_INS];
    sockets.length = 0;
    await act(async () => {
      root.render(
        createElement(
          MemoryRouter,
          { initialEntries: ['/create-ai'] },
          createElement(Routes, null, createElement(Route, { path: '/create-ai', element: createElement(CreateAiCharacterPage) })),
        ),
      );
    });
    await settle();
  }
  const stepDot = (label: string) =>
    Array.from(container.querySelectorAll<HTMLButtonElement>('.step-dot')).find((b) => b.textContent?.includes(label))!;
  const pill = () => container.querySelector('.cg-tpl-from');

  it('Load fills the form and keeps the typed name; the pill shows on Output until the character is saved', async () => {
    await openPage();
    expect(container.textContent).toContain('Pick a template, or a mode to start blank.');
    const name = container.querySelector<HTMLInputElement>('.cg-field input')!;
    type(name, 'Aria Vale');
    await click(button('Harbor town, slow burn'));
    expect(button(/Guided Creator/).getAttribute('aria-pressed')).toBe('true');
    expect(name.value).toBe('Aria Vale');
    expect(tileNamed('Harbor').classList.contains('on')).toBe(true);

    await click(button(/^Next: Details/));
    expect(container.querySelector('textarea')!.value).toBe('A lighthouse keeper.');
    await click(button(/^Next: Output/));
    await settle();
    expect(pill()!.textContent).toBe('Started from: Harbor town, slow burn');

    // Saved: the mark is gone when the form is looked at again.
    await act(async () => {
      for (const s of sockets) s({ event: 'chargen_done', id: 7 });
    });
    await settle();
    await click(stepDot('Output'));
    await settle();
    expect(container.querySelector('[data-testid="template-save"]')).not.toBeNull();
    expect(pill()).toBeNull();
  });
});
