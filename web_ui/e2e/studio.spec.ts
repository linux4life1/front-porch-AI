// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The story studio's own chrome, end to end against the real app: the header
// (rename, delete), Overview ("what is next", the bible edited in place) and the
// Structure board before anything is planned. Nothing here needs a model: the
// story is created empty and only saved, renamed and deleted.

import type { Page } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';

async function newStory(page: Page, title: string): Promise<string> {
  const created = (await (await page.request.post('/api/stories', { data: { title } })).json()) as { id: string };
  return created.id;
}

const titles = async (page: Page) =>
  ((await (await page.request.get('/api/stories')).json()) as { stories: { title: string }[] }).stories.map((s) => s.title);

test('the studio header renames and deletes a story, with the delete confirm in the page', async ({ page }) => {
  const id = await newStory(page, 'Studio Header Journey');
  await openRoute(page, `/stories/${id}`);
  await expect(page.getByRole('heading', { name: 'Studio Header Journey' })).toBeVisible();

  await page.getByTestId('studio-menu').click();
  await page.getByRole('menuitem', { name: 'Rename' }).click();
  await page.getByTestId('story-rename').fill('Studio Header Renamed');
  await page.getByRole('dialog', { name: 'Rename' }).getByRole('button', { name: 'Rename' }).click();
  await expect(page.getByRole('heading', { name: 'Studio Header Renamed' })).toBeVisible();
  expect(await titles(page)).toContain('Studio Header Renamed');

  // Export has nothing to export until something is written.
  await page.getByTestId('studio-menu').click();
  await expect(page.getByRole('menuitem', { name: 'Export eBook (.epub)' })).toBeDisabled();
  await page.getByRole('menuitem', { name: 'Delete story…' }).click();
  const confirm = page.getByRole('dialog', { name: 'Delete Studio Header Renamed?' });
  await expect(confirm).toContainText('Its setup and bible will be removed. This cannot be undone.');
  await confirm.getByRole('button', { name: 'Cancel' }).click();
  await expect(confirm).toHaveCount(0);
  expect(await titles(page)).toContain('Studio Header Renamed');

  await page.getByTestId('studio-menu').click();
  await page.getByRole('menuitem', { name: 'Delete story…' }).click();
  await page.getByTestId('story-confirm').click();
  await expect(page).toHaveURL(/\/stories$/);
  expect(await titles(page)).not.toContain('Studio Header Renamed');
});

test('Overview says what is next and lets the bible be edited in place; Structure waits for the bible', async ({ page }) => {
  const id = await newStory(page, 'Studio Overview Journey');
  await openRoute(page, `/stories/${id}`);
  const upNext = page.getByTestId('studio-up-next');
  await expect(upNext).toContainText('The bible is not built');
  await expect(upNext).toContainText('Cast, themes, threads and lore come from your idea.');
  await expect(page.getByTestId('story-build-bible')).toBeEnabled();

  await page.getByTestId('story-edit-concept').click();
  await page.getByTestId('story-bible-field').fill('A courier on a drowned coast owes a smuggler forty silver.');
  await page.getByRole('dialog', { name: 'Concept' }).getByRole('button', { name: 'Save' }).click();
  await expect(page.getByTestId('studio-bible')).toContainText('A courier on a drowned coast owes a smuggler forty silver.');
  // It was saved, not just shown: the project comes back with it.
  const saved = (await (await page.request.get(`/api/stories/${id}`)).json()) as { concept: string };
  expect(saved.concept).toBe('A courier on a drowned coast owes a smuggler forty silver.');

  await page.getByTestId('studio-nav-structure').click();
  await expect(page.getByTestId('story-empty-structure')).toContainText('No structure yet');
  await expect(page.getByTestId('story-empty-structure')).toContainText('Build the bible first; the acts follow from it.');
  await expect(page.getByTestId('story-continue')).toBeDisabled();
});
