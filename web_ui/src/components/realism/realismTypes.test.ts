// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web half of the inventory data-loss fix.
//
// CharacterEditPage sends `...rv` wholesale, where `rv` is whatever
// realismFromDetail built out of the server's `realism` block. That makes this
// model the gate: a field it does not carry is a field every save drops.
//
// The Dart bridge omitted `inventory` in BOTH directions, so editing a
// character from a phone wiped whatever starting Pockets & Wardrobe its author
// had written — with no inventory control on the page to hint that the save had
// touched it. The Dart side is fixed and guarded in
// test/services/web/inventory_bridge_test.dart; this is the other end of the
// same round trip.

import { describe, expect, it } from 'vitest';

import {
  REALISM_DEFAULTS,
  chipsToInventory,
  compactGreetingPairs,
  inventoryToChips,
  realismFromDetail,
} from './realismTypes';

describe('inventory survives detail -> form -> save body', () => {
  const stored = {
    worn: [{ name: 'flour-dusted apron', state: 'well-worn' }],
    carrying: ['shop keys'],
  };

  it('carries the stored record off the detail block', () => {
    const rv = realismFromDetail({ inventory: stored });

    expect(rv.inventory).toEqual(stored);
  });

  it('keeps item condition, which is half of what Pockets tracks', () => {
    const worn = realismFromDetail({ inventory: stored }).inventory.worn!;

    expect(worn[0]).toEqual({ name: 'flour-dusted apron', state: 'well-worn' });
  });

  it('reaches the save body through the spread the edit page uses', () => {
    // Not a redundant restatement of the first case: the edit page builds its
    // POST as `{...fields, ...rv}`, so what matters is that the key is present
    // on the spread result — which is what breaks if the field is dropped from
    // the interface and TypeScript starts eliding it.
    const rv = realismFromDetail({ inventory: stored });
    const body = { name: 'Jennifer', description: 'edited', ...rv };

    expect(body).toHaveProperty('inventory');
    expect((body as typeof rv).inventory).toEqual(stored);
  });

  it('carries greetingSeeds off the detail block so a phone save cannot drop them', () => {
    const seeds = [{ characterEmotion: 'furious', shortTermBond: -40 }];
    const rv = realismFromDetail({ greetingSeeds: seeds });
    const body = { name: 'Nemu', ...rv };
    expect(body.greetingSeeds).toEqual(seeds);
  });

  it('defaults greetingSeeds to an empty list, never undefined', () => {
    expect(REALISM_DEFAULTS.greetingSeeds).toEqual([]);
    expect(realismFromDetail(null).greetingSeeds).toEqual([]);
  });

  it('defaults to an empty record, never undefined', () => {
    // Undefined would reach the Dart side as a missing key. That is survivable
    // there (it falls back to the stored value) but it would mean the web could
    // never deliberately clear an inventory, which an authoring UI has to do.
    expect(REALISM_DEFAULTS.inventory).toEqual({});
    expect(realismFromDetail(null).inventory).toEqual({});
    expect(realismFromDetail(undefined).inventory).toEqual({});
  });

  it('a card with no realism block at all does not crash', () => {
    expect(() => realismFromDetail({}).inventory).not.toThrow();
    expect(realismFromDetail({}).inventory).toEqual({});
  });
});

// ── Wardrobe chip text ──────────────────────────────────────────────────────
// These cases are deliberately the SAME ones as
// test/services/chat/wardrobe_authoring_test.dart. The desktop and web editors
// write to one field on one card; if the two conversions disagree about where
// a condition starts, a character edited on a phone and the same character
// edited on the desktop end up with different items — and neither side would
// look wrong on its own. Keeping the tables identical is what makes a drift
// visible.

describe('wardrobe chip text mirrors the Dart implementation', () => {
  const roundTrips = [
    'car keys',
    'sundress (rain-soaked)',
    'iron sword (notched, needs sharpening)',
    'pepper spray (small)',
    'a candy bar (half-eaten)',
    'keys ()',
    'a (b) c',
  ];

  it.each(roundTrips)('display round-trips exactly: %s', (text) => {
    expect(inventoryToChips(chipsToInventory([text], [])).worn[0]).toBe(text);
  });

  it('a trailing bracket becomes the condition', () => {
    expect(chipsToInventory(['sundress (rain-soaked)'], []).worn).toEqual([
      { name: 'sundress', state: 'rain-soaked' },
    ]);
  });

  it('no brackets means no condition', () => {
    expect(chipsToInventory(['car keys'], []).worn).toEqual([{ name: 'car keys' }]);
  });

  it('an empty half on either side stays part of the name', () => {
    expect(chipsToInventory(['keys ()'], []).worn).toEqual([{ name: 'keys ()' }]);
  });

  it('does not save a wearing chip named nothing', () => {
    expect(chipsToInventory(['nothing', 'red sundress'], []).worn).toEqual([
      { name: 'red sundress' },
    ]);
    expect(chipsToInventory(['nude'], []).worn).toBeUndefined();
  });

  it('only the last bracket group is considered', () => {
    expect(chipsToInventory(['flask (dented) (empty)'], []).worn).toEqual([
      { name: 'flask (dented)', state: 'empty' },
    ]);
  });

  it('collapses whitespace, as the prompt-hardening on the Dart side does', () => {
    expect(chipsToInventory(['  car   keys \n'], []).worn).toEqual([{ name: 'car keys' }]);
  });

  it('drops blank chips', () => {
    expect(chipsToInventory(['', '   ', 'apron'], []).worn).toHaveLength(1);
  });

  it('caps item text at 60 characters', () => {
    const [item] = chipsToInventory([`${'x'.repeat(200)} (${'y'.repeat(200)})`], []).worn!;
    expect((item as { name: string }).name.length).toBeLessThanOrEqual(60);
    expect((item as { state: string }).state.length).toBeLessThanOrEqual(60);
  });

  it('caps each list at 8 items', () => {
    const many = Array.from({ length: 13 }, (_, i) => `thing ${i}`);
    expect(chipsToInventory(many, []).worn).toHaveLength(8);
  });

  it('an empty wardrobe stays ABSENT from the card', () => {
    // Same load-bearing property as the Dart side: CharacterCard.toJson emits
    // `inventory` only when non-empty, and two protected goldens pin cards
    // without the key. An editor that wrote {worn:[],carrying:[]} would add a
    // key to every card written anywhere.
    expect(chipsToInventory([], [])).toEqual({});
    expect(chipsToInventory(['', '  '], [''])).toEqual({});
    expect(chipsToInventory(['apron'], [])).not.toEqual({});
  });

  it('reads the plain-string shape a hand-written card may use', () => {
    expect(inventoryToChips({ worn: ['sundress'], carrying: ['car keys'] })).toEqual({
      worn: ['sundress'],
      carrying: ['car keys'],
    });
  });

  it('survives a card with nothing, or junk, in the field', () => {
    expect(inventoryToChips(undefined)).toEqual({ worn: [], carrying: [] });
    expect(inventoryToChips({})).toEqual({ worn: [], carrying: [] });
    expect(() => inventoryToChips({ worn: 'apron' as never })).not.toThrow();
  });

  it('a reopened editor saves the identical card', () => {
    const worn = ['sundress (rain-soaked)'];
    const carrying = ['car keys', 'a candy bar (half-eaten)'];

    const first = chipsToInventory(worn, carrying);
    const reopened = inventoryToChips(first);
    expect(chipsToInventory(reopened.worn, reopened.carrying)).toEqual(first);
    expect(reopened.worn).toEqual(worn);
    expect(reopened.carrying).toEqual(carrying);
  });
});

describe('compactGreetingPairs keeps seed on the surviving greet', () => {
  it('drops the blank row and keeps furious on Get out.', () => {
    const paired = compactGreetingPairs(['', 'Get out.'], [null, { characterEmotion: 'furious' }]);
    expect(paired.greetings).toEqual(['Get out.']);
    expect(paired.seeds).toEqual([{ characterEmotion: 'furious' }]);
  });

  it('a blank middle row does not steal furious off Get out.', () => {
    const paired = compactGreetingPairs(
      ['Come in.', '', 'Get out.'],
      [null, { characterEmotion: 'stolen' }, { characterEmotion: 'furious' }],
    );
    expect(paired.greetings).toEqual(['Come in.', 'Get out.']);
    expect(paired.seeds).toEqual([null, { characterEmotion: 'furious' }]);
  });
});
