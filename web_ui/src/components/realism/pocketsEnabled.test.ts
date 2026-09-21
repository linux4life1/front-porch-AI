// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-character Pockets & Wardrobe on the web Realism form model.
// Missing /detail key must stay on so old cards keep working.

import { describe, expect, it } from 'vitest';

import { REALISM_DEFAULTS, realismFromDetail } from './realismTypes';

describe('pocketsEnabled on the web realism form', () => {
  it('defaults on so a new card does not silently veto Pockets', () => {
    expect(REALISM_DEFAULTS.pocketsEnabled).toBe(true);
    expect(realismFromDetail(null).pocketsEnabled).toBe(true);
    expect(realismFromDetail({}).pocketsEnabled).toBe(true);
  });

  it('preserves explicit off from /detail through the edit-page spread', () => {
    const rv = realismFromDetail({ pocketsEnabled: false });
    expect(rv.pocketsEnabled).toBe(false);
    const body = { name: 'Bea', ...rv };
    expect(body.pocketsEnabled).toBe(false);
  });
});
