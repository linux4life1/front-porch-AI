// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new group is named after all its members until the user types a name.

import { describe, it, expect } from 'vitest';
import { defaultGroupName } from './groupName';

describe('defaultGroupName', () => {
  it('lists every member, then counts past three', () => {
    expect(defaultGroupName([])).toBe('');
    expect(defaultGroupName(['Juniper'])).toBe('Juniper');
    expect(defaultGroupName(['Juniper', 'Marlow'])).toBe('Juniper & Marlow');
    expect(defaultGroupName(['Juniper', 'Marlow', 'Ivy'])).toBe('Juniper, Marlow & Ivy');
    expect(defaultGroupName(['Juniper', 'Marlow', 'Ivy', 'Rowan'])).toBe('Juniper & 3 others');
  });

  it('skips blank names', () => {
    expect(defaultGroupName(['Juniper', ' ', 'Marlow'])).toBe('Juniper & Marlow');
  });
});
