// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Context Budget legend: the Realism section is the Realism Engine (it
// said "Realism Mode"), in the colour desktop's LegendColors.contextSections
// gives it, and a send saved before the rename keeps that colour.

import { expect, it } from 'vitest';

import { SECTION_COLORS } from './ContextBudgetModal';

it('colours the Realism Engine section, and a saved "Realism Mode" one, the same', () => {
  expect(SECTION_COLORS['Realism Engine']).toBe('#EC4899');
  expect(SECTION_COLORS['Realism Mode']).toBe(SECTION_COLORS['Realism Engine']);
});
