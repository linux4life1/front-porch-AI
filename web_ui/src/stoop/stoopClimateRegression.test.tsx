// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { StoopBadges } from '../components/stoop/StoopCardTile';
import { StoopCardSections } from '../pages/stoop/StoopCardSections';
import {
  stoopCardClimateEnabled,
  stoopWorldClimate,
  stoopWorldClimateEnabled,
  stoopWorldTraits,
} from './stoopCardBody';
import type { StoopCard, StoopCardDetail } from './stoopTypes';

function world(overrides: Partial<StoopCard> = {}): StoopCard {
  return {
    id: 'world-1',
    name: 'Lore Shelf',
    summary: 'A place made of facts.',
    type: 'WORLD',
    nsfw: false,
    score: 0,
    downloadCount: 0,
    modPick: false,
    creator: null,
    primaryAssetId: null,
    tokenCount: null,
    ...overrides,
  };
}

function detail(card: Record<string, unknown>): StoopCardDetail {
  return {
    ...world(),
    version: 1,
    card,
    tags: [],
    myVote: 0,
  };
}

describe('Stoop WORLD climate boundaries', () => {
  it('uses list metadata without treating an omitted card as climate-on', () => {
    expect(stoopCardClimateEnabled(world())).toBe(false);
    expect(stoopCardClimateEnabled(world({ climateEnabled: true }))).toBe(
      true,
    );
    expect(stoopCardClimateEnabled(world({ climate_enabled: false }))).toBe(
      false,
    );
  });

  it('keeps genuine old envelopes climate-on and honors envelope flags', () => {
    expect(
      stoopCardClimateEnabled(world({ card: { biome: { id: 'desert' } } })),
    ).toBe(true);
    expect(stoopWorldClimateEnabled({ biome: { id: 'desert' } })).toBe(true);
    expect(
      stoopWorldClimateEnabled({
        climate_enabled: 'invalid',
        climateEnabled: false,
      }),
    ).toBe(false);
    expect(
      stoopCardClimateEnabled({
        ...world({ climateEnabled: false }),
        card: { climate_enabled: 'invalid' },
      }),
    ).toBe(false);
    expect(
      stoopCardClimateEnabled({
        ...world({ climateEnabled: false }),
        card: { climate_enabled: true },
      }),
    ).toBe(true);
  });

  it('hides leftover detail climate and traits when climate is off', () => {
    const card = {
      climate_enabled: false,
      biome: { displayName: 'Leftover climate' },
      place_traits: { gravity: 'low' },
    };

    expect(stoopWorldClimate(card)).toBe('');
    expect(stoopWorldTraits(card)).toEqual([]);
  });
});

describe('Stoop WORLD climate surfaces', () => {
  it('labels list rows and detail sections as lore-only', () => {
    const badges = renderToStaticMarkup(
      <StoopBadges card={world({ climateEnabled: false })} />,
    );
    expect(badges).toContain('World');
    expect(badges).toContain('Lore');
    expect(badges).not.toContain('Climate');

    const sections = renderToStaticMarkup(
      <StoopCardSections
        detail={detail({
          description: 'Facts without weather.',
          climate_enabled: false,
          biome: { displayName: 'Leftover climate' },
          place_traits: { gravity: 'low' },
          lorebook: { entries: [] },
        })}
      />,
    );
    expect(sections).toContain(
      'Lore only -- no climate, weather, or place traits.',
    );
    expect(sections).not.toContain('Leftover climate');
    expect(sections).not.toContain('Traits');
  });
});
