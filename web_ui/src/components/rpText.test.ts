// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for RP text coloring (dialogue / action / emphasis), incl. the
// stripMarkers flag that keeps composer-overlay text character-aligned. Inspects
// the returned React nodes directly — no DOM, no pixels, synthetic strings only.

import { describe, it, expect } from 'vitest';
import { isValidElement, type ReactElement } from 'react';
import { renderRpInline } from './rpText';

function spans(text: string, strip = true): { cls: unknown; text: unknown }[] {
  return renderRpInline(text, 't', strip)
    .filter(isValidElement)
    .map((n) => {
      const e = n as ReactElement<{ className?: string; children?: unknown }>;
      return { cls: e.props.className, text: e.props.children };
    });
}

describe('renderRpInline', () => {
  it('colors straight "dialogue" amber (.dlg), keeping its quotes', () => {
    expect(spans('She said "hello there" softly')).toContainEqual({ cls: 'dlg', text: '"hello there"' });
  });

  it('colors curly “dialogue” too', () => {
    expect(spans('She said “hi” quietly')).toContainEqual({ cls: 'dlg', text: '“hi”' });
  });

  it('colors *action* blue and strips the asterisks for display', () => {
    expect(spans('*waves a hand*')).toContainEqual({ cls: 'act', text: 'waves a hand' });
  });

  it('colors **emphasis** as bold action and strips the markers', () => {
    expect(spans('**finally**')).toContainEqual({ cls: 'act bold', text: 'finally' });
  });

  it('keeps every marker char when stripMarkers=false (composer alignment)', () => {
    expect(spans('*waves*', false)).toContainEqual({ cls: 'act', text: '*waves*' });
    expect(spans('**bold**', false)).toContainEqual({ cls: 'act bold', text: '**bold**' });
  });

  it('leaves non-RP text as plain strings', () => {
    expect(renderRpInline('just narration', 't').some((n) => n === 'just narration')).toBe(true);
  });
});
