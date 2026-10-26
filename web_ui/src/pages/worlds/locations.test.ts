// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure guards for the web library planner and the prose-injection twin
// (slice 4). These mirror the Dart law's expectations (the same fixtures
// world_library_rows_test uses); the relay still owns legality — these
// pin that the CLIENT RENDERS the same shape the desktop shows.

import { describe, expect, it } from 'vitest';

import {
  buildWorldInjection,
  indexById,
  injectionUsedChars,
  libraryDisplayOrder,
  planWorldLibrary,
  placesUnder,
  type TreeWorld,
} from './locations';

function w(
  name: string,
  extra: Partial<TreeWorld> = {},
): TreeWorld {
  return { id: name, name, ...extra };
}

describe('planWorldLibrary', () => {
  const town = w('Bletchfield');
  const hall = w('Town Hall', { parentWorldId: 'Bletchfield' });
  const tea = w('Tea Rooms', { parentWorldId: 'Bletchfield' });
  const station = w('Red Dust Station');
  const ghost = w('Ghost Room', { parentWorldId: 'gone' });
  const shadow = w('Shadow Hall', {
    parentWorldId: 'Bletchfield',
    isModelMade: true,
  });
  const library = [town, station, hall, tea, ghost, shadow];

  it('groups roots with children into sections; childless and dangling stay flat', () => {
    const plan = planWorldLibrary(library, 'all');
    expect(plan.sections).toHaveLength(1);
    expect(plan.sections[0].root.id).toBe('Bletchfield');
    expect(plan.sections[0].children.map((c) => c.id)).toEqual([
      'Shadow Hall',
      'Tea Rooms',
      'Town Hall',
    ]);
    expect(plan.flat.map((f) => f.id)).toEqual([
      'Red Dust Station',
      'Ghost Room',
    ]);
  });

  it('a root never renders twice', () => {
    const plan = planWorldLibrary(library, 'all');
    const ids = [
      ...plan.sections.map((s) => s.root.id),
      ...plan.flat.map((f) => f.id),
    ];
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('roots only: no child cards anywhere', () => {
    const plan = planWorldLibrary(library, 'rootsOnly');
    expect(plan.sections[0].children).toEqual([]);
    expect(plan.flat.map((f) => f.id)).toContain('Red Dust Station');
    for (const f of plan.flat) {
      expect(f.parentWorldId == null || f.id === 'Ghost Room').toBe(true);
    }
  });

  it('model-made: only the flagged worlds, at any depth', () => {
    const plan = planWorldLibrary(library, 'modelMade');
    expect(plan.sections).toEqual([]);
    expect(plan.flat.map((f) => f.id)).toEqual(['Shadow Hall']);
  });

  it('no locations renders exactly the pre-locations flat list', () => {
    const flatOnly = [station, ghost];
    const plan = planWorldLibrary(flatOnly, 'all');
    expect(plan.sections).toEqual([]);
    expect(plan.flat.map((f) => f.id)).toEqual([
      'Red Dust Station',
      'Ghost Room',
    ]);
  });

  it('a ring surfaces flat instead of vanishing', () => {
    const a = w('A', { parentWorldId: 'B' });
    const b = w('B', { parentWorldId: 'A' });
    const plan = planWorldLibrary([a, b], 'all');
    expect(plan.sections).toEqual([]);
    expect(plan.flat.map((f) => f.id).sort()).toEqual(['A', 'B']);
  });

  it('placesUnder counts direct children only', () => {
    const byId = indexById(library);
    expect(placesUnder('Bletchfield', library, byId)).toBe(3);
    const room = w('Back Room', { parentWorldId: 'Town Hall' });
    const deeper = [...library, room];
    expect(placesUnder('Bletchfield', deeper, indexById(deeper))).toBe(3);
    expect(placesUnder('Town Hall', deeper, indexById(deeper))).toBe(1);
  });

  it('libraryDisplayOrder puts every parent before its children', () => {
    const town = w('Bletchport');
    const hall = w('Town Hall', { parentWorldId: 'Bletchport' });
    const room = w('Back Room', { parentWorldId: 'Town Hall' });
    const lone = w('Red Dust Station');
    const order = libraryDisplayOrder([room, hall, lone, town]).map(
      (x) => x.id,
    );
    expect(order.indexOf('Bletchport')).toBeLessThan(order.indexOf('Town Hall'));
    expect(order.indexOf('Town Hall')).toBeLessThan(order.indexOf('Back Room'));
  });
});

describe('buildWorldInjection (Dart twin)', () => {
  it('names the block and lists leaf first', () => {
    const town = w('Bletchport', { description: 'Harbour lamps and salt wind.' });
    const room = w('The Lighthouse', {
      description: 'Warm lamplight over cold rope and tar.',
      parentWorldId: 'Bletchport',
    });
    const text = buildWorldInjection([room, town]);
    expect(text.startsWith('Setting — where you are:\n')).toBe(true);
    expect(text.indexOf('The Lighthouse')).toBeLessThan(
      text.indexOf('Bletchport'),
    );
  });

  it('the leaf wins the budget; an over-budget parent truncates and stops', () => {
    const big = 'x'.repeat(550);
    const town = w('Bletchport', { description: big });
    const room = w('The Lighthouse', {
      description: 'Small room prose.',
      parentWorldId: 'Bletchport',
    });
    const text = buildWorldInjection([room, town]);
    expect(text).toContain('Small room prose.');
    expect(injectionUsedChars(text)).toBeLessThanOrEqual(600);
  });

  it('traits survive description truncation (behavior beats flavor)', () => {
    const big = 'x'.repeat(560);
    const parent = w(
      'Bletchport',
      { description: big, atmosphere: 'thin', climateEnabled: true },
    );
    const room = w('Room', {
      description: 'cozy',
      parentWorldId: 'Bletchport',
    });
    const text = buildWorldInjection([room, parent]);
    expect(text).toContain('air is thin');
    // Parity pin, not an ideal: the Dart descBudget formula spends one
    // char more than `remain` in the truncate path (two separators
    // subtracted, three written), and the join adds another — the twin
    // reproduces 602 exactly, not a fixed-up 600. Fixing it means
    // changing world_injection.dart and its goldens, both out of scope
    // here; THE NUMBER THE PREVIEW SHOWS MUST BE THE NUMBER THE ENGINE
    // SPENDS.
    expect(injectionUsedChars(text)).toBe(602);
  });

  it('climate-off places keep descriptions but emit no trait lines', () => {
    const off = w('Cold Vault', {
      description: 'Dusty shelves.',
      atmosphere: 'hostile',
      climateEnabled: false,
    });
    const text = buildWorldInjection([off]);
    expect(text).toContain('Dusty shelves.');
    expect(text).not.toContain('hostile');
  });

  it('injectDescription off blanks the prose but keeps behavior', () => {
    const off = w('Vent Shaft', {
      description: 'Prose the author hid.',
      injectDescription: false,
      atmosphere: 'hostile',
      climateEnabled: true,
    });
    const text = buildWorldInjection([off]);
    expect(text).not.toContain('Prose the author hid.');
    expect(text).toContain('The air itself is hostile');
  });

  it('the counter is exactly one above the joined body (Dart budgets a separator per block)', () => {
    const a = w('A', { description: 'aaa' });
    const b = w('B', { description: 'bbb', parentWorldId: 'A' });
    const text = buildWorldInjection([b, a]);
    const body = text.slice('Setting — where you are:\n'.length);
    expect(injectionUsedChars(text)).toBe(body.length + 1);
  });
});

describe('buildWorldInjection under a weather-off top-level world', () => {
  const greenhouse = w('The Greenhouse', {
    description: 'Warm glass rooms.',
    atmosphere: 'thin',
    climateEnabled: true,
    parentWorldId: 'Earth',
  });

  it('silences the traits of a place that owns a climate', () => {
    const earth = w('Earth', { climateEnabled: false });
    const text = buildWorldInjection([greenhouse, earth]);
    expect(text).toContain('Warm glass rooms.');
    expect(text).not.toContain('air is thin');
  });

  it('the same place speaks its traits once the root is on', () => {
    const earth = w('Earth', { climateEnabled: true });
    expect(buildWorldInjection([greenhouse, earth])).toContain('air is thin');
  });
});

describe('buildWorldInjection: trait lines come from the climate author only', () => {
  const moon = w('Grey Moon', {
    description: 'Dust under a black sky.',
    atmosphere: 'unbreathable',
    gravity: 'low',
    climateEnabled: true,
  });
  const wheel = (extra: Partial<TreeWorld>) =>
    w('The Wheel', {
      description: 'Parks and canals under a long sunlit strip.',
      parentWorldId: 'Grey Moon',
      ...extra,
    });

  it("a place that owns its climate silences the root's traits", () => {
    const text = buildWorldInjection([wheel({ climateEnabled: true }), moon]);
    expect(text).toContain('Parks and canals');
    expect(text).toContain('Dust under a black sky.');
    expect(text).not.toContain('unbreathable');
    expect(text).not.toContain('Gravity is low');
  });

  it("a place that inherits gets the root's trait lines", () => {
    const text = buildWorldInjection([wheel({ climateEnabled: false }), moon]);
    expect(text).toContain('unbreathable');
    expect(text).toContain('Gravity is low');
  });

  it('a place that owns climate and traits speaks only its own', () => {
    const text = buildWorldInjection([wheel({ climateEnabled: true, gravity: 'high' }), moon]);
    expect(text).toContain('Gravity is high');
    expect(text).not.toContain('Gravity is low');
    expect(text).not.toContain('unbreathable');
  });
});
