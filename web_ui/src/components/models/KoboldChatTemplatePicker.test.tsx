// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wrong-template warning on the Models page: shown until the user keeps
// the template anyway, which the host remembers for that template and model.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { post } = vi.hoisted(() => ({ post: vi.fn() }));
vi.mock('../../api/client', () => ({ api: { post }, ApiError: class extends Error {} }));

import { KoboldChatTemplatePicker } from './KoboldChatTemplatePicker';
import type { LocalModel } from './KoboldStatusCard';

type Preset = NonNullable<LocalModel['preset']>;

const WARNED: Preset = {
  path: '/k/Long chats.kcpps',
  name: 'Long chats',
  words: '',
  chatTemplate: 'chat_templates/abc/qwen.jinja',
  chatTemplateEditable: true,
  chatTemplateWarning: {
    message: 'This template may not fit Mistral 7B. It writes <|im_end|>, which the model does not know.',
    missing: ['<|im_end|>'],
    modelMarkers: [],
  },
};

let container: HTMLDivElement;
let root: Root;
let preset: Preset;

function show() {
  act(() => {
    root.render(createElement(KoboldChatTemplatePicker, {
      preset,
      onSaved: (card: LocalModel) => { preset = card.preset!; show(); },
    }));
  });
}

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find((b) => b.textContent === label);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockReset();
  preset = WARNED;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('KoboldChatTemplatePicker warning', () => {
  it('shows the warning and keeps the template when Use anyway is tapped', async () => {
    show();
    expect(container.textContent).toContain('may not fit Mistral 7B');
    post.mockResolvedValue({ preset: { ...WARNED, chatTemplateWarning: null } });
    await act(async () => { button('Use anyway')!.click(); });
    expect(post).toHaveBeenCalledWith('/api/backend/local-model/chat-template/accept', {
      preset: WARNED.path,
    });
    expect(container.textContent).not.toContain('may not fit');
    expect(container.textContent).toContain('qwen.jinja');
  });

  it('offers no Use anyway on a preset the phone cannot edit', () => {
    preset = { ...WARNED, chatTemplateEditable: false };
    show();
    expect(container.textContent).toContain('may not fit Mistral 7B');
    expect(button('Use anyway')).toBeUndefined();
  });
});
