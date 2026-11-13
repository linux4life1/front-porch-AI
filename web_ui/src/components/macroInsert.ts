// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared helper for inserting template macros ({{char}}, {{user}}) into
// prompt textareas. Preserves the native DOM undo stack when focused, and
// falls back to smart-appending at the end when unfocused.

/**
 * Appends a macro to a string with smart spacing: adds a leading space if
 * the existing string is non-empty and does not already end in whitespace.
 */
export function appendSmartMacro(current: string, macro: string): string {
  if (!current) return macro;
  if (/\s$/.test(current)) return current + macro;
  return current + ' ' + macro;
}

/**
 * Inserts a macro into a textarea element.
 *
 * If the textarea is focused, inserts at the current caret or replaces the
 * current selection while preserving the browser's native undo stack
 * (document.execCommand('insertText') / setRangeText with input event).
 *
 * If the textarea is not focused, appends to the end using smart spacing.
 */
export function insertPromptMacro(
  textarea: HTMLTextAreaElement | null,
  currentValue: string,
  macro: string,
  onChange: (nextValue: string) => void,
): void {
  if (!textarea) {
    const next = appendSmartMacro(currentValue, macro);
    onChange(next);
    return;
  }

  const isFocused = document.activeElement === textarea;

  if (isFocused) {
    const start = textarea.selectionStart ?? currentValue.length;
    const end = textarea.selectionEnd ?? currentValue.length;

    textarea.focus();
    let inserted = false;
    try {
      inserted = document.execCommand('insertText', false, macro);
    } catch {
      inserted = false;
    }

    if (inserted) {
      onChange(textarea.value);
    } else if (typeof textarea.setRangeText === 'function') {
      textarea.setRangeText(macro, start, end, 'end');
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      onChange(textarea.value);
    } else {
      const next = currentValue.slice(0, start) + macro + currentValue.slice(end);
      onChange(next);
      const newPos = start + macro.length;
      requestAnimationFrame(() => {
        textarea.focus();
        textarea.setSelectionRange(newPos, newPos);
      });
    }
  } else {
    const next = appendSmartMacro(currentValue, macro);
    onChange(next);
    requestAnimationFrame(() => {
      textarea.focus();
      const pos = next.length;
      textarea.setSelectionRange(pos, pos);
    });
  }
}
