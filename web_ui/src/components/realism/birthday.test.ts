// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';

import { realismFromDetail } from './realismTypes';

describe('birthday survives detail -> form -> save body', () => {
  it('carries YYYY-MM-DD off the detail block', () => {
    const rv = realismFromDetail({ birthday: '1998-03-15' });
    expect(rv.birthday).toBe('1998-03-15');
  });

  it('defaults to empty, never undefined', () => {
    expect(realismFromDetail(null).birthday).toBe('');
  });
});
