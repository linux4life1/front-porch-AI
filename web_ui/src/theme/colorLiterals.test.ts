// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Every web colour follows the app theme. The desktop sends the resolved
// tokens (theme/appTheme.ts); a hex, rgb() or hsl() literal in a CSS rule or
// a component stays the same colour in light mode and in every theme. This
// ratchet fails any file that has more literals than BASELINE allows, and
// any baseline that is looser than the file now needs, so the count only
// goes down.
//
// Allowed without counting: a `--token: …;` definition inside a `:root`
// block (the dark defaults), black inside a *-shadow declaration, and a line
// that carries `theme-keep: <reason>` for a colour fixed in every theme
// (a brand mark, a QR code's white, a legend, a crop fill). Comments are
// ignored, so issue numbers like #370 are not colours.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it } from 'vitest';

const SRC = join(__dirname, '..');

/** Files still holding literals, and how many. Shrink it; never grow it. */
const BASELINE: Record<string, number> = {};

const LITERAL = /#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\(/g;
const BLACK = /^(?:#000(?:000)?(?:[0-9a-fA-F]{2})?|rgba?\(0,\s*0,\s*0\b|rgba?\(0 0 0\b)/;

function filesUnder(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return filesUnder(p);
    return /\.(css|tsx?)$/.test(name) && !name.includes('.test.') ? [p] : [];
  });
}

/** Blank out comments, keeping line breaks so line numbers still line up. */
function stripComments(text: string, css: boolean): string {
  const blank = (m: string) => m.replace(/[^\n]/g, ' ');
  const block = text.replace(/\/\*[\s\S]*?\*\//g, blank);
  return css ? block : block.replace(/(^|[^:'"`])\/\/.*$/gm, (m, lead: string) => lead + blank(m.slice(lead.length)));
}

/** Uncounted literals in one file, as `line: text`. */
export function themeLiterals(text: string, css: boolean): string[] {
  const raw = text.split('\n');
  const lines = stripComments(text, css).split('\n');
  const hits: string[] = [];
  let depth = 0;
  let rootDepth = -1;
  let declaration = '';
  lines.forEach((line, i) => {
    if (raw[i].includes('theme-keep:') || (i > 0 && /^\s*(?:\/\/|\/\*).*theme-keep:/.test(raw[i - 1]))) return;
    if (css && rootDepth < 0 && /:root\s*\{/.test(line)) rootDepth = depth;
    const inRoot = css && rootDepth >= 0;
    if (css) {
      const prop = /([a-z-]+)\s*:/.exec(line);
      if (prop && !line.trim().startsWith('.') && !line.trim().startsWith(':')) declaration = prop[1];
      else if (/\{/.test(line)) declaration = (/\{\s*([a-z-]+)\s*:/.exec(line) ?? [])[1] ?? '';
    }
    for (const m of line.matchAll(LITERAL)) {
      const at = m.index ?? 0;
      const before = line.slice(0, at);
      const decl = css ? (/([a-z-]+)\s*:[^:;{]*$/.exec(before) ?? [])[1] ?? declaration : '';
      if (inRoot && decl.startsWith('--')) continue;
      if (css && /shadow$/.test(decl) && BLACK.test(line.slice(at))) continue;
      if (css && /drop-shadow\([^)]*$/.test(before) && BLACK.test(line.slice(at))) continue;
      hits.push(`${i + 1}: ${raw[i].trim()}`);
      break;
    }
    if (css) {
      for (const ch of line) {
        if (ch === '{') depth++;
        if (ch === '}') {
          depth--;
          if (depth === rootDepth) rootDepth = -1;
        }
      }
    }
  });
  return hits;
}

describe('web colour literals', () => {
  const counts = Object.fromEntries(
    filesUnder(SRC).map((p) => [relative(SRC, p), themeLiterals(readFileSync(p, 'utf8'), p.endsWith('.css'))]),
  );

  it('no file holds more literals than its baseline', () => {
    const over = Object.entries(counts)
      .filter(([f, hits]) => hits.length > (BASELINE[f] ?? 0))
      .map(([f, hits]) => `${f} (${hits.length} > ${BASELINE[f] ?? 0}):\n  ${hits.join('\n  ')}`);
    expect(over, 'Use a var(--token) from base.css, or mark a colour fixed in every theme with theme-keep: <reason>').toEqual([]);
  });

  it('the baseline is as tight as the files', () => {
    const loose = Object.entries(BASELINE)
      .filter(([f, n]) => (counts[f]?.length ?? 0) < n)
      .map(([f, n]) => `${f}: baseline ${n}, now ${counts[f]?.length ?? 0}`);
    expect(loose, 'Lower these entries (delete them at 0)').toEqual([]);
  });

  it('catches a literal in a rule and ignores the allowed kinds', () => {
    const css = [
      ':root {',
      '  --bg: #1b1611;',
      '}',
      '.a { color: #fff; }',
      '.b { box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4); }',
      '.c { box-shadow: 0 0 8px rgba(244, 162, 89, 0.4); }',
      '.d { fill: #e8b923; } /* theme-keep: brand check */',
      '/* issue #370 */',
      '.e { background: color-mix(in srgb, var(--accent) 14%, transparent); }',
    ].join('\n');
    expect(themeLiterals(css, true)).toEqual([
      '4: .a { color: #fff; }',
      '6: .c { box-shadow: 0 0 8px rgba(244, 162, 89, 0.4); }',
    ]);
    expect(themeLiterals("const a = '#3B82F6'; // #161\nconst b = 'var(--info)';", false)).toEqual([
      "1: const a = '#3B82F6'; // #161",
    ]);
  });
});
