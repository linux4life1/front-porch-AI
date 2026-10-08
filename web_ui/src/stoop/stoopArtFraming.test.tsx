// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Stoop card art framing matches the hub and the desktop app: portrait
// tiles crop from the top, world tiles get a 16:10 landscape frame centred,
// and the card page shows the whole picture at its own height.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { renderToStaticMarkup } from 'react-dom/server';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { StoopCardTile } from '../components/stoop/StoopCardTile';
import type { StoopCard } from './stoopTypes';

function card(type: StoopCard['type']): StoopCard {
  return {
    id: 'c-1',
    name: 'Roxy',
    summary: 'A goat herder on a ridge.',
    type,
    nsfw: false,
    score: 0,
    downloadCount: 0,
    modPick: false,
    creator: null,
    primaryAssetId: 'asset-1',
    tokenCount: null,
  };
}

function tile(type: StoopCard['type']): string {
  return renderToStaticMarkup(
    <MemoryRouter>
      <StoopCardTile card={card(type)} />
    </MemoryRouter>,
  );
}

const STYLES = join(__dirname, '..', 'styles');
const stoopCss = readFileSync(join(STYLES, 'stoop.css'), 'utf8');
const libCss = readFileSync(join(STYLES, 'library-cards.css'), 'utf8');

describe('Stoop art framing', () => {
  it('only world tiles carry the landscape class', () => {
    expect(tile('WORLD')).toContain('stoop-tile-world');
    expect(tile('SOLO')).not.toContain('stoop-tile-world');
    expect(tile('GROUP')).not.toContain('stoop-tile-world');
  });

  it('portrait tiles crop from the top', () => {
    expect(libCss).toMatch(/\.lib-art img \{[^}]*object-position: top center/);
  });

  it('world tiles get a 16:10 frame, centred', () => {
    expect(stoopCss).toMatch(/\.stoop-tile-world \.lib-art \{[^}]*aspect-ratio: 16 \/ 10/);
    expect(stoopCss).toMatch(/\.stoop-tile-world \.lib-art img \{[^}]*object-position: center/);
  });

  it('the card page shows the whole picture instead of a 3:4 crop', () => {
    expect(stoopCss).toMatch(/\.stoop-detail-art \{[^}]*aspect-ratio: auto/);
    expect(stoopCss).toMatch(/\.lib-art\.stoop-detail-art img \{[^}]*height: auto/);
  });
});
