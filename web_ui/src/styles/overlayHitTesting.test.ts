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

// The notch, home bar and cutouts are handled in one place (styles/
// safe-area.css) so no screen has to remember them. A chat header that
// forgot put the sidebar button under an iPhone 11's notch.
describe('safe area has one owner', () => {
  const SAFE_FILE = join(SRC, 'styles', 'safe-area.css');
  const safeCss = readFileSync(SAFE_FILE, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const TOKEN_FALLBACK = /var\(--fp-safe-(top|right|bottom|left),\s*env\(safe-area-inset-\1\)\)/g;

  it('the page starts below the iOS status bar on every device', () => {
    const html = readFileSync(join(SRC, '..', 'index.html'), 'utf8').replace(/<!--[\s\S]*?-->/g, '');
    expect(html).toMatch(/name="apple-mobile-web-app-status-bar-style"\s+content="default"/);
    expect(html).not.toMatch(/black-translucent/);
  });

  it('only safe-area.css reads env(safe-area-inset-*)', () => {
    const offenders: string[] = [];
    for (const file of [...filesUnder(join(SRC, 'styles'), /\.css$/), ...filesUnder(SRC, /\.tsx?$/)]) {
      if (file === SAFE_FILE) continue;
      const text = readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(TOKEN_FALLBACK, '');
      if (/env\(\s*safe-area-inset/.test(text)) offenders.push(file.slice(SRC.length + 1));
    }
    expect(offenders, 'read var(--fp-safe-*) instead; safe-area.css owns the insets').toEqual([]);
  });

  it('#root and the tokens live in safe-area.css', () => {
    for (const edge of ['top', 'right', 'bottom', 'left']) {
      expect(safeCss).toMatch(new RegExp(`--fp-safe-${edge}:\\s*env\\(safe-area-inset-${edge}`));
    }
    expect(safeCss).toMatch(
      /#root\s*\{[^}]*padding:\s*var\(--fp-safe-top\)\s+var\(--fp-safe-right\)\s+var\(--fp-safe-bottom\)\s+var\(--fp-safe-left\)/,
    );
    const shell = readFileSync(join(SRC, 'styles', 'shell.css'), 'utf8');
    expect(shell).toMatch(/height:\s*calc\(100dvh - var\(--fp-safe-top\) - var\(--fp-safe-bottom\)\)/);
  });

  it('every fixed layer is in safe-area.css or says why it needs nothing', () => {
    const listed = new Set(
      [...safeCss.matchAll(/([^{}]+)\{[^{}]*border-width:\s*var\(--fp-safe-top\)[^{}]*\}/g), ...safeCss.matchAll(/([^{}]+)\{[^{}]*padding-top:\s*var\(--fp-safe-top\)[^{}]*\}/g)]
        .flatMap(([, sel]) => sel.split(','))
        .map((s) => s.trim().replace(/\s+/g, ' ')),
    );
    const unhandled: string[] = [];
    for (const file of filesUnder(join(SRC, 'styles'), /\.css$/)) {
      if (file === SAFE_FILE) continue;
      // Keep comments: a `safe-area:` marker inside the rule is its reason.
      const css = readFileSync(file, 'utf8');
      for (const [, selectors, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        if (!/position\s*:\s*fixed/.test(body.replace(/\/\*[\s\S]*?\*\//g, ''))) continue;
        if (/safe-area:/.test(body)) continue;
        for (const raw of selectors.replace(/\/\*[\s\S]*?\*\//g, '').split(',')) {
          const sel = raw.trim().replace(/\s+/g, ' ');
          if (!listed.has(sel)) unhandled.push(`${file.slice(SRC.length + 1)}: ${sel}`);
        }
      }
    }
    expect(unhandled, 'list the layer in safe-area.css, or mark the rule /* safe-area: <why> */').toEqual([]);
  });
});
