// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tiles load the postcard thumb (what the hub site does) and only the card
// page asks the relay for the original.

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { StoopCardArt } from '../components/stoop/StoopCardTile';
import { stoop } from './stoopApi';

describe('Stoop asset URLs', () => {
  it('defaults to the thumb variant', () => {
    expect(stoop.assetUrl('a 1')).toBe('/api/stoop/assets/a%201?v=thumb');
    expect(stoop.assetUrl('a 1', { thumb: true })).toBe('/api/stoop/assets/a%201?v=thumb');
    expect(stoop.assetUrl('a 1', { thumb: false })).toBe('/api/stoop/assets/a%201');
  });

  it('card art is a thumb unless asked for the original', () => {
    const tile = renderToStaticMarkup(<StoopCardArt assetId="x" name="Roxy" />);
    const page = renderToStaticMarkup(<StoopCardArt assetId="x" name="Roxy" full />);
    expect(tile).toContain('/api/stoop/assets/x?v=thumb');
    expect(page).toContain('/api/stoop/assets/x"');
    expect(page).not.toContain('v=thumb');
  });
});
