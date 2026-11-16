// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's portrait rail (PR 8d): the three sources, the no-engine
// banner, the portrait prompt seed, the ZIP import, and the expression pack's
// CTA and start. Vision QC is deliberately absent.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('react-router-dom', () => ({ useNavigate: () => vi.fn() }));
vi.mock('../ImageCropModal', () => ({
  ImageCropModal: ({ onCropped }: { onCropped: (b: Blob) => void }) =>
    createElement('button', { 'data-testid': 'crop', onClick: () => onCropped(new Blob(['x'])) }, 'crop'),
}));

type Call = { path: string; body?: unknown };
const posts: Call[] = [];
const uploads: { path: string; name: string }[] = [];
let ready = { ready: true, line: 'ComfyUI · model.safetensors', primary: 'model.safetensors' };
let packView: Record<string, unknown> = {
  running: false,
  canImport: false,
  imported: null,
  done: 0,
  total: 0,
  slots: [],
};

vi.mock('../../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path.includes('/studio/ready')) return ready;
      if (path.includes('/avatars')) return { avatars: [] };
      if (path.includes('/expression-pack')) return packView;
      return {};
    },
    post: async (path: string, body?: unknown) => {
      posts.push({ path, body });
      if (path.includes('/expression-pack')) return packView;
      return {};
    },
    upload: async (path: string, file: File) => {
      uploads.push({ path, name: file.name });
      return { ok: true, avatars: [], added: 2, unrecognized: 1 };
    },
  },
  ApiError: class ApiError extends Error {},
}));

const { AvatarRail } = await import('./AvatarRail');

let container: HTMLDivElement;
let root: Root;
const busy: boolean[] = [];

async function settle() {
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
}

const button = (scope: Element, text: RegExp) => {
  const b = Array.from(scope.querySelectorAll('button')).find(
    (x) => text.test(x.textContent ?? '') || text.test(x.getAttribute('aria-label') ?? ''),
  );
  if (!b) throw new Error(`no button ${text}`);
  return b as HTMLButtonElement;
};

async function click(b: HTMLButtonElement) {
  await act(async () => {
    b.click();
  });
  await settle();
}

async function render() {
  act(() => {
    root.render(
      createElement(AvatarRail, {
        characterId: '7',
        seed: 'character portrait, Anime style, a vampire lecturer',
        description: 'A vampire lecturer.',
        onBusyChange: (b: boolean) => busy.push(b),
      }),
    );
  });
  await settle();
}

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  uploads.length = 0;
  busy.length = 0;
  ready = { ready: true, line: 'ComfyUI · model.safetensors', primary: 'model.safetensors' };
  packView = { running: false, canImport: false, imported: null, done: 0, total: 0, slots: [] };
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await render();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('AvatarRail', () => {
  it('offers the three sources, the banner and the upload caption', () => {
    expect(container.textContent).toContain('PORTRAIT — PICK A SOURCE');
    expect(button(container, /Upload my own/)).not.toBeNull();
    expect(button(container, /Generate/)).not.toBeNull();
    expect(button(container, /None for now/)).not.toBeNull();
    expect(container.textContent).toContain(
      'First image is the portrait; add more as gallery looks, or tag one with an emotion',
    );
    expect(container.textContent).toContain('EXPRESSIONS — INDEPENDENT OF THE PORTRAIT SOURCE');
    expect(button(container, /Import ZIP/)).not.toBeNull();
  });

  it('shows the no-engine banner and disables Generate', async () => {
    act(() => root.unmount());
    ready = { ready: false, line: 'No image engine is set up.' };
    root = createRoot(container);
    await render();
    expect(container.textContent).toContain(
      'Generate is unavailable — no image engine is set up. Configure one, or upload images instead.',
    );
    expect(button(container, /Generate/).disabled).toBe(true);
  });

  it('opens Generate on the portrait prompt seed', async () => {
    await click(button(container, /Generate/));
    const prompt = container.querySelector('textarea[aria-label="Portrait prompt"]') as HTMLTextAreaElement;
    expect(prompt.value).toBe('character portrait, Anime style, a vampire lecturer');
    expect(button(container, /Generate portrait/)).not.toBeNull();
  });

  it('imports a ZIP and reports what landed and what did not', async () => {
    const input = container.querySelector('input[accept=".zip,application/zip"]') as HTMLInputElement;
    const file = new File(['zip'], 'expressions.zip', { type: 'application/zip' });
    Object.defineProperty(input, 'files', { value: [file] });
    await act(async () => {
      input.dispatchEvent(new Event('change', { bubbles: true }));
    });
    await settle();
    expect(uploads.at(-1)?.path).toBe('/api/characters/7/expressions/import-zip');
    expect(container.textContent).toContain('Imported 2 expression images; 1 file not recognised.');
  });

  it('starts the expression pack with the chosen set', async () => {
    await act(async () => {
      (container.querySelector('.cg-r-expr input.switch') as HTMLInputElement).click();
    });
    await settle();
    const select = container.querySelector('.cg-r-pack select') as HTMLSelectElement;
    Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')!.set!.call(select, 'full');
    await act(async () => {
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(button(container, /Generate 28 expressions/)).not.toBeNull();
    await click(button(container, /Generate 28 expressions/));
    expect(posts.at(-1)?.path).toBe('/api/image/expression-pack');
    expect(posts.at(-1)?.body).toMatchObject({
      characterId: '7',
      set: 'full',
      workspace: false,
      baseSource: 'currentPortrait',
      prompt: 'A vampire lecturer.',
    });
  });
});
