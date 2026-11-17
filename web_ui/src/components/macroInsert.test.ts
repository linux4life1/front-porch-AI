// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it, vi } from 'vitest';
import { appendSmartMacro, insertPromptMacro } from './macroInsert';

describe('appendSmartMacro', () => {
  it('returns macro when current string is empty', () => {
    expect(appendSmartMacro('', '{{char}}')).toBe('{{char}}');
  });

  it('adds a leading space when current string does not end in whitespace', () => {
    expect(appendSmartMacro('Be concise', '{{char}}')).toBe('Be concise {{char}}');
  });

  it('does not add a leading space when current string ends in a space', () => {
    expect(appendSmartMacro('Be concise ', '{{char}}')).toBe('Be concise {{char}}');
  });

  it('does not add a leading space when current string ends in a newline', () => {
    expect(appendSmartMacro('Be concise\n', '{{char}}')).toBe('Be concise\n{{char}}');
  });
});

describe('insertPromptMacro', () => {
  it('appends to end with smart spacing when textarea is not focused', () => {
    const textarea = document.createElement('textarea');
    textarea.value = 'Be concise';
    document.body.appendChild(textarea);
    // Ensure textarea is not active element
    textarea.blur();

    const onChange = vi.fn();
    insertPromptMacro(textarea, 'Be concise', '{{char}}', onChange);

    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith('Be concise {{char}}');
    textarea.remove();
  });

  it('appends to empty string when unfocused', () => {
    const textarea = document.createElement('textarea');
    textarea.value = '';
    document.body.appendChild(textarea);
    textarea.blur();

    const onChange = vi.fn();
    insertPromptMacro(textarea, '', '{{user}}', onChange);

    expect(onChange).toHaveBeenCalledWith('{{user}}');
    textarea.remove();
  });

  it('inserts at exact caret position when textarea is focused', () => {
    const textarea = document.createElement('textarea');
    textarea.value = 'Hello world';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.setSelectionRange(5, 5);

    const onChange = vi.fn();
    insertPromptMacro(textarea, 'Hello world', '{{char}}', onChange);

    expect(onChange).toHaveBeenCalledWith('Hello{{char}} world');
    textarea.remove();
  });

  it('replaces exact selection range when textarea is focused', () => {
    const textarea = document.createElement('textarea');
    textarea.value = 'Hello world';
    document.body.appendChild(textarea);
    textarea.focus();
    // Select "world" (indices 6 to 11)
    textarea.setSelectionRange(6, 11);

    const onChange = vi.fn();
    insertPromptMacro(textarea, 'Hello world', '{{char}}', onChange);

    expect(onChange).toHaveBeenCalledWith('Hello {{char}}');
    textarea.remove();
  });

  it('inserts at index 0 if textarea is focused and caret is explicitly at 0', () => {
    const textarea = document.createElement('textarea');
    textarea.value = 'world';
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.setSelectionRange(0, 0);

    const onChange = vi.fn();
    insertPromptMacro(textarea, 'world', 'Hello ', onChange);

    expect(onChange).toHaveBeenCalledWith('Hello world');
    textarea.remove();
  });

  it('handles null textarea gracefully by calling onChange with smart-appended string', () => {
    const onChange = vi.fn();
    insertPromptMacro(null, 'Rules', '{{char}}', onChange);
    expect(onChange).toHaveBeenCalledWith('Rules {{char}}');
  });
});
