// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act, createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, expect, it, vi } from 'vitest';
import { PackDraft } from './PackDraft';
import type { Picture } from './DeskRail';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

let root: Root;
let host: HTMLDivElement;
afterEach(() => {
  if (root) act(() => root.unmount());
  host?.remove();
});

it('keeps its own description and source through hide/show, and freezes both with a pack', () => {
  const createPrompt = vi.fn();
  const problem = vi.fn();
  const reload = vi.fn();
  function Workspace() {
    const [hidden, setHidden] = useState(false);
    const [frozen, setFrozen] = useState(false);
    const [description, setDescription] = useState('pack only');
    const [picture, setPicture] = useState<Picture | null>(null);
    return createElement('div', null,
      createElement('button', { onClick: () => setHidden((value) => !value) }, 'Switch workspace'),
      createElement('button', { onClick: () => setFrozen(true) }, 'Capture pack'),
      createElement('textarea', { 'aria-label': 'Create prompt', defaultValue: 'create only', onChange: createPrompt }),
      createElement('div', { hidden }, createElement(PackDraft, {
        description, onDescription: setDescription, picture, onPicture: setPicture,
        portrait: 'card-portrait.png', portraitLoading: false, characterName: 'Character',
        lastSaved: { name: 'studio.png', url: 'studio.png' }, frozen, onProblem: problem, onReloadPortrait: reload,
      })),
    );
  }
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  act(() => root.render(createElement(Workspace)));
  const click = (text: string) => act(() => {
    [...host.querySelectorAll('button')].find((button) => button.textContent === text)!.click();
  });
  const description = host.querySelector<HTMLTextAreaElement>('[aria-label="Pack description"]')!;
  click('Reload current card portrait');
  expect(reload).toHaveBeenCalledOnce();
  act(() => {
    Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value')!.set!.call(description, 'independent draft');
    description.dispatchEvent(new Event('input', { bubbles: true }));
  });
  click('Use last Studio picture for pack');
  expect(host.querySelector('img')!.getAttribute('src')).toBe('studio.png');
  expect(host.textContent).toContain('Source: studio.png');
  expect(createPrompt).not.toHaveBeenCalled();
  expect(host.querySelector<HTMLTextAreaElement>('[aria-label="Create prompt"]')!.value).toBe('create only');
  click('Switch workspace');
  expect(description.closest('[hidden]')).not.toBeNull();
  click('Switch workspace');
  expect(host.querySelector('[aria-label="Pack description"]')).toBe(description);
  expect(description.value).toBe('independent draft');
  click('Capture pack');
  expect(host.querySelector('fieldset')!.disabled).toBe(true);
  click('Use current card portrait');
  expect(host.querySelector('img')!.getAttribute('src')).toBe('studio.png');
  expect(problem).not.toHaveBeenCalled();
});

it('cancels an unfinished picture read when the target changes', async () => {
  const onPicture = vi.fn();
  const onLoading = vi.fn();
  const props = {
    description: '', onDescription: vi.fn(), picture: null, onPicture,
    portrait: 'card.png', portraitLoading: false, characterName: 'Character',
    frozen: false, onProblem: vi.fn(), onPictureLoading: onLoading,
  };
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  act(() => root.render(createElement(PackDraft, { ...props, characterId: 'first' })));
  const input = host.querySelector<HTMLInputElement>('input[type="file"]')!;
  act(() => {
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['picture'], 'portrait.png', { type: 'image/png' })] });
    input.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(onLoading).toHaveBeenCalledWith(true);
  act(() => root.render(createElement(PackDraft, { ...props, characterId: 'second' })));
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  expect(onLoading).toHaveBeenLastCalledWith(false);
  expect(onPicture).not.toHaveBeenCalled();
});

it('keeps the saved source when an earlier picture upload finishes', async () => {
  const onPicture = vi.fn();
  const onLoading = vi.fn();
  const saved = { name: 'studio.png', url: 'studio.png' };
  host = document.createElement('div');
  document.body.append(host);
  root = createRoot(host);
  act(() => root.render(createElement(PackDraft, {
    description: 'portrait', onDescription: vi.fn(), picture: null, onPicture,
    portrait: 'card.png', portraitLoading: false, characterName: 'Character',
    lastSaved: saved, frozen: false, onProblem: vi.fn(), onPictureLoading: onLoading,
  })));
  const input = host.querySelector<HTMLInputElement>('input[type="file"]')!;
  act(() => {
    Object.defineProperty(input, 'files', { configurable: true, value: [new File(['picture'], 'upload.png', { type: 'image/png' })] });
    input.dispatchEvent(new Event('change', { bubbles: true }));
  });
  expect(onLoading).toHaveBeenLastCalledWith(true);
  act(() => {
    [...host.querySelectorAll('button')].find((button) => button.textContent === 'Use last Studio picture for pack')!.click();
  });
  await act(async () => { await new Promise((resolve) => setTimeout(resolve, 20)); });
  expect(onPicture).toHaveBeenCalledExactlyOnceWith({ kind: 'saved', ...saved });
  expect(onLoading).toHaveBeenLastCalledWith(false);
});
