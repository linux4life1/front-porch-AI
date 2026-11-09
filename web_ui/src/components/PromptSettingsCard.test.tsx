// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The PromptSettingsCard in Settings → General: 3 stacked cards (Option A:
// Fallback system prompt, Group system prompt, Global prompt additions)
// with macro badge chips and clean card hierarchy.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PromptSettingsCard } from './PromptSettingsCard';

let host: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});

afterEach(() => {
  act(() => root.unmount());
  host.remove();
  vi.restoreAllMocks();
});

describe('PromptSettingsCard', () => {
  it('renders the three prompt cards in Option A order with macro chips', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'You are an AI companion.',
          systemPromptName: null,
          groupSystemPrompt: 'Group context.',
          groupSystemPromptName: null,
          additionalSystemPrompt: 'Extra system rules.',
          additionalPostHistoryInstructions: 'Post history note.',
          savedPrompts: [],
          builtInSystemPrompts: [{ label: 'Standard', text: 'You are an AI companion.' }],
          builtInGroupSystemPrompt: 'Default group base.',
          patch,
        }),
      );
    });

    const fallbackCard = host.querySelector('[data-testid="fallback-system-prompt"]');
    const groupCard = host.querySelector('[data-testid="group-system-prompt"]');
    const globalAdditions = host.querySelector('[data-testid="global-prompt-additions"]');

    expect(fallbackCard).not.toBeNull();
    expect(groupCard).not.toBeNull();
    expect(globalAdditions).not.toBeNull();

    // Verify ordering: Fallback first, Group second, Global additions third
    const allCards = Array.from(host.querySelectorAll('[data-testid]'));
    const testIds = allCards.map((el) => el.getAttribute('data-testid'));
    const fallbackIdx = testIds.indexOf('fallback-system-prompt');
    const groupIdx = testIds.indexOf('group-system-prompt');
    const globalIdx = testIds.indexOf('global-prompt-additions');

    expect(fallbackIdx).toBeLessThan(groupIdx);
    expect(groupIdx).toBeLessThan(globalIdx);

    // Verify macro chips exist in fallback prompt
    const macroChips = fallbackCard?.querySelectorAll('.macro-chip');
    expect(macroChips?.length).toBeGreaterThanOrEqual(2);
    expect(macroChips?.[0].textContent).toContain('{{char}}');
    expect(macroChips?.[1].textContent).toContain('{{user}}');
  });

  it('clicking a macro chip in fallback prompt inserts {{char}} into prompt', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'Hello',
          systemPromptName: null,
          groupSystemPrompt: '',
          groupSystemPromptName: null,
          savedPrompts: [],
          builtInSystemPrompts: [],
          patch,
        }),
      );
    });

    const fallbackCard = host.querySelector('[data-testid="fallback-system-prompt"]');
    const charBtn = fallbackCard?.querySelector<HTMLButtonElement>('button[title*="character"]');
    expect(charBtn).not.toBeNull();

    await act(async () => {
      charBtn?.click();
    });

    // Verify patch was called with macro appended/inserted
    expect(patch).toHaveBeenCalledWith(
      expect.objectContaining({
        systemPrompt: expect.stringContaining('{{char}}'),
      }),
    );
  });

  it('clicking a macro chip in global prompt additions inserts {{user}}', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'Hello',
          systemPromptName: null,
          groupSystemPrompt: '',
          groupSystemPromptName: null,
          additionalSystemPrompt: 'System line',
          additionalPostHistoryInstructions: 'Post line',
          savedPrompts: [],
          builtInSystemPrompts: [],
          patch,
        }),
      );
    });

    const globalAdditions = host.querySelector('[data-testid="global-prompt-additions"]');
    const userBtns = globalAdditions?.querySelectorAll<HTMLButtonElement>('button[title*="user"]');
    expect(userBtns?.length).toBeGreaterThanOrEqual(2);

    await act(async () => {
      userBtns?.[0].click();
    });

    expect(patch).toHaveBeenCalledWith(
      expect.objectContaining({
        additionalSystemPrompt: expect.stringContaining('{{user}}'),
      }),
    );
  });
});
