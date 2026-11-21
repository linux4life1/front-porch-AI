// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The editor header (character, group member, Edit group) on a phone: a long
// name used to break mid-word ("Meadow / s,") in the ~110 px the whole-width
// Cancel / Save buttons leave. On a phone the title now takes its own row
// above the buttons, one line ending in "…" (the desktop's
// TextOverflow.ellipsis); wide still wraps a long title, but only between
// words. jsdom does no layout, so the rules themselves are pinned; the PR
// screenshots show the render.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { expect, it } from 'vitest';

const css = readFileSync(resolve(__dirname, 'shell.css'), 'utf8');
const rule = (selector: string) => {
  const at = css.indexOf(`${selector} {`);
  expect(at, `no rule for ${selector}`).toBeGreaterThanOrEqual(0);
  return css.slice(at, css.indexOf('}', at));
};

it('the editor title never breaks inside a word', () => {
  expect(rule('.page-head.editor-head > h2')).toMatch(/overflow-wrap: break-word/);
  expect(css).not.toMatch(/editor-head[^{]*\{[^}]*overflow-wrap: anywhere/);
});

it('on a phone the title takes its own row, one line ending in an ellipsis', () => {
  expect(rule('[data-layout="phone"] .page-head.editor-head')).toMatch(/flex-wrap: wrap/);
  const h2 = rule('[data-layout="phone"] .page-head.editor-head > h2');
  expect(h2).toMatch(/flex: 1 0 100%/);
  expect(h2).toMatch(/white-space: nowrap/);
  expect(h2).toMatch(/text-overflow: ellipsis/);
  expect(h2).toMatch(/overflow: hidden/);
});
