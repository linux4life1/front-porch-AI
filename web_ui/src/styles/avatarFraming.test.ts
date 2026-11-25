// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Portrait crops on the web match the desktop widget that draws the same
// surface. The desktop anchors these at the top (Alignment.topCenter), so a
// tall portrait in a square or 16:9 frame keeps the face; the web default
// (object-position: 50% 50%) shows the chest instead.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const STYLES = __dirname;
const REPO = join(__dirname, '..', '..', '..');

/** The declarations of the first rule whose selector is exactly `selector`. */
function ruleBody(cssFile: string, selector: string): string {
  const css = readFileSync(join(STYLES, cssFile), 'utf8');
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const m = new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`).exec(css);
  if (!m) throw new Error(`${selector} not found in ${cssFile}`);
  return m[1];
}

const TOP_ANCHORED: Array<{ surface: string; css: string; selector: string; dart: string }> = [
  {
    surface: 'chat sidebar portrait',
    css: 'chat.css',
    selector: '.portrait',
    dart: 'lib/ui/chat_components/sidebar/character_portrait.dart',
  },
  {
    surface: 'avatar gallery tile',
    css: 'wizard.css',
    selector: '.avatar-tile img',
    dart: 'lib/ui/dialogs/avatar_gallery/avatar_tile.dart',
  },
  {
    surface: 'Stoop creator avatar',
    css: 'stoop.css',
    selector: '.stoop-creator-ava img',
    dart: 'lib/ui/pages/repository/stoop_avatar.dart',
  },
];

describe('avatar framing matches the desktop', () => {
  it.each(TOP_ANCHORED)('$surface crops from the top on both', ({ css, selector, dart }) => {
    expect(readFileSync(join(REPO, dart), 'utf8')).toContain('Alignment.topCenter');
    expect(ruleBody(css, selector)).toMatch(/object-position:\s*top center/);
  });
});
