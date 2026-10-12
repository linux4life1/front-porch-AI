// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A user lost hours of work: leaving a page threw unsaved edits away
// without a word. Against the real app, leaving a form with typed input now
// asks first.

import { expect, openRoute, test } from './support/fixtures';

// Leaving a form with unsaved input asks first (the desktop's
// UnsavedChangesGuard question). "No" keeps the page and what was typed;
// "Yes" leaves. Nothing is created, so there is nothing to clean up.
test('leaving Create Character with a typed name asks first; staying keeps it', async ({ page, acceptConfirms }) => {
  const asked: string[] = [];
  page.on('dialog', (d) => asked.push(d.message()));
  await openRoute(page, '/create');
  const name = page.locator('.wizard-body input').first();
  await name.fill('Unsaved Journey');
  const home = page.getByRole('link', { name: 'Front Porch AI', exact: true });

  await home.click();
  await expect.poll(() => asked.length).toBe(1);
  expect(asked[0]).toContain('Discard unsaved changes?');
  await expect(page).toHaveURL(/#\/create$/);
  await expect(name).toHaveValue('Unsaved Journey');

  acceptConfirms(true);
  await home.click();
  await expect(page).toHaveURL(/#\/$/);
  expect(asked).toHaveLength(2);
});
