// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The PromptSettingsCard in Settings → General: 3 stacked cards (Option A:
// Fallback system prompt, Group system prompt, Global prompt additions)
// with desktop parity on prompt slots and macro badge chips on global additions.

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
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
  it('renders the three prompt cards in Option A order with desktop parity', async () => {
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

    // Desktop parity: Fallback and Group slots have NO macro chips
    expect(fallbackCard?.querySelectorAll('.macro-chip').length).toBe(0);
    expect(groupCard?.querySelectorAll('.macro-chip').length).toBe(0);

    // Global additions has macro chips
    const globalChips = globalAdditions?.querySelectorAll('.macro-chip');
    expect(globalChips?.length).toBeGreaterThanOrEqual(2);
  });

  it('unfocused macro click in global additions smart-appends to the end with exact string', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'Hello',
          systemPromptName: null,
          groupSystemPrompt: '',
          groupSystemPromptName: null,
          additionalSystemPrompt: 'Be concise',
          additionalPostHistoryInstructions: 'Post line',
          savedPrompts: [],
          builtInSystemPrompts: [],
          patch,
        }),
      );
    });

    const globalAdditions = host.querySelector('[data-testid="global-prompt-additions"]');
    const textarea = host.querySelector<HTMLTextAreaElement>('#add-system-instructions');
    expect(textarea).not.toBeNull();
    textarea?.blur();

    const charBtn = globalAdditions?.querySelector<HTMLButtonElement>('button[title*="character"]');
    expect(charBtn).not.toBeNull();

    await act(async () => {
      charBtn?.click();
    });

    // Exact string assertion: "Be concise {{char}}" (not "{{char}}Be concise")
    expect(patch).toHaveBeenCalledWith({
      additionalSystemPrompt: 'Be concise {{char}}',
    });
  });

  it('unfocused macro click on empty prompt sets exact macro string without leading space', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'Hello',
          systemPromptName: null,
          groupSystemPrompt: '',
          groupSystemPromptName: null,
          additionalSystemPrompt: '',
          additionalPostHistoryInstructions: '',
          savedPrompts: [],
          builtInSystemPrompts: [],
          patch,
        }),
      );
    });

    const globalAdditions = host.querySelector('[data-testid="global-prompt-additions"]');
    const textarea = host.querySelector<HTMLTextAreaElement>('#add-system-instructions');
    textarea?.blur();

    const charBtn = globalAdditions?.querySelector<HTMLButtonElement>('button[title*="character"]');

    await act(async () => {
      charBtn?.click();
    });

    expect(patch).toHaveBeenCalledWith({
      additionalSystemPrompt: '{{char}}',
    });
  });

  it('focused macro click inserts at exact caret position', async () => {
    const patch = vi.fn();
    await act(async () => {
      root.render(
        createElement(PromptSettingsCard, {
          systemPrompt: 'Hello',
          systemPromptName: null,
          groupSystemPrompt: '',
          groupSystemPromptName: null,
          additionalSystemPrompt: 'Always speak to  as a friend',
          additionalPostHistoryInstructions: '',
          savedPrompts: [],
          builtInSystemPrompts: [],
          patch,
        }),
      );
    });

    const textarea = host.querySelector<HTMLTextAreaElement>('#add-system-instructions');
    expect(textarea).not.toBeNull();
    textarea?.focus();
    // Caret right between the two spaces (index 16)
    textarea?.setSelectionRange(16, 16);

    const userBtns = host.querySelectorAll<HTMLButtonElement>('button[title*="user"]');
    expect(userBtns.length).toBeGreaterThanOrEqual(1);

    await act(async () => {
      userBtns[0].click();
    });

    expect(patch).toHaveBeenCalledWith({
      additionalSystemPrompt: 'Always speak to {{user}} as a friend',
    });
  });
});
