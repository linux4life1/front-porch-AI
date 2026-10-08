// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Overlays and dialogs must stay tappable. #330: the message editor's overlay
// shared `msg-edit-backdrop` with the highlight layer behind its textarea, so
// that layer's `pointer-events: none` landed on the whole modal and every
// Save / Cancel / text tap fell through to the transcript. Scans the real
// stylesheets and every overlay/dialog className in the TSX for that collision.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const SRC = join(__dirname, '..');

function filesUnder(dir: string, ext: RegExp): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return filesUnder(p, ext);
    return ext.test(name) && !name.includes('.test.') ? [p] : [];
  });
}

/** Class sets (one compound selector each) that a rule makes untappable. */
function untappableCompounds(): string[][] {
  const out: string[][] = [];
  for (const file of filesUnder(join(SRC, 'styles'), /\.css$/)) {
    const css = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    for (const [, selectors, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      if (!/pointer-events\s*:\s*none/.test(body)) continue;
      for (const selector of selectors.split(',')) {
        const last = selector.trim().split(/[\s>+~]+/).pop() ?? '';
        if (/^(\.[\w-]+)+$/.test(last)) out.push(last.slice(1).split('.'));
      }
    }
  }
  return out;
}

/** Literal class lists on overlay roots and dialog panels. */
function overlayClassLists(): { file: string; classes: string[] }[] {
  const out: { file: string; classes: string[] }[] = [];
  for (const file of filesUnder(SRC, /\.tsx$/)) {
    const tsx = readFileSync(file, 'utf8');
    for (const [, list] of tsx.matchAll(/className=["{`]+([^"`}$]+)/g)) {
      const classes = list.trim().split(/\s+/);
      if (classes.includes('drawer-backdrop') || classes.includes('modal')) {
        out.push({ file: file.slice(SRC.length + 1), classes });
      }
    }
  }
  return out;
}

describe('overlay hit-testing', () => {
  it('finds the stylesheet rules and overlays it guards', () => {
    expect(untappableCompounds().length).toBeGreaterThan(0);
    expect(overlayClassLists().length).toBeGreaterThan(20);
  });

  it('no overlay or dialog carries a class that disables pointer events', () => {
    const compounds = untappableCompounds();
    const clashes = overlayClassLists().flatMap(({ file, classes }) =>
      compounds
        .filter((c) => c.every((cls) => classes.includes(cls)))
        .map((c) => `${file}: "${classes.join(' ')}" matches .${c.join('.')}`),
    );
    expect(clashes).toEqual([]);
  });

  // Dialogs (regenerate, variant picker) render inside the transcript. A
  // z-index on the themed chat view's children makes each one a stacking
  // context, so the composer — a later sibling — paints over those dialogs'
  // backdrops and stays tappable whenever a chat has a theme background.
  it('themed chat children do not trap the dialogs inside them', () => {
    const css = readFileSync(join(SRC, 'styles', 'chat.css'), 'utf8').replace(
      /\/\*[\s\S]*?\*\//g,
      '',
    );
    const rule = /\.chat-view\.has-theme-bg\s*>\s*\*\s*\{([^}]*)\}/.exec(css);
    expect(rule).not.toBeNull();
    expect(rule![1]).not.toMatch(/z-index/);
  });

  // #330 follow-up: a 100dvh sheet centered in the overlay slides under the
  // iOS status bar once the keyboard pans the layout viewport. The phone
  // sheet tracks the visual viewport and pads every safe-area edge.
  it('the phone message editor is not a centered 100dvh sheet (#330)', () => {
    const css = ['messages.css', 'places.css']
      .map((name) => readFileSync(join(SRC, 'styles', name), 'utf8').replace(/\/\*[\s\S]*?\*\//g, ''))
      .join('\n');
    expect(css).not.toMatch(/\.msg-edit-modal[^{]*\{[^}]*100dvh/);
    expect(css).toMatch(
      /\[data-layout="phone"\]\s+\.drawer-backdrop\.msg-edit-overlay\s*\{[^}]*align-items:\s*flex-start/,
    );
    expect(css).toMatch(/height:\s*var\(--fp-vvh,\s*100%\)/);
    expect(css).toMatch(/top:\s*var\(--fp-vv-top,\s*0px\)/);
    expect(css).toMatch(/var\(--fp-safe-top,\s*env\(safe-area-inset-top\)\)/);
    expect(css).toMatch(/var\(--fp-safe-bottom,\s*env\(safe-area-inset-bottom\)\)/);
    expect(css).toMatch(/var\(--fp-safe-left,\s*env\(safe-area-inset-left\)\)/);
    expect(css).toMatch(/var\(--fp-safe-right,\s*env\(safe-area-inset-right\)\)/);
    expect(css).toMatch(/\.msg-edit-scroll\s*\{[^}]*min-height:\s*0/);
  });
});
