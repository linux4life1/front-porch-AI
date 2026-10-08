// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The user's own chat length comes back on the phone (maintainer ruling I,
// 2026-10-05): a preset sets the context while it is chosen, and going back
// to automatic puts back the context the user had picked before, not the
// preset's. Against the real app; the host seeds a local model and the 32k
// "Long chats" preset (browser_test.dart). Nothing here loads a model.

import type { Page } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';

const setBackend = (page: Page, backend: 'kobold' | 'openRouter') =>
  page.request.post('/api/settings', { data: { backend } });

const savedContext = async (page: Page) =>
  ((await (await page.request.get('/api/settings')).json()) as { contextSize: number }).contextSize;

test.describe('the user’s own context', () => {
  // The stand-in backend as the suite set it up, put back afterwards with no
  // preset and the context the host seeded, whatever happened.
  let standIn: { backend: string; remoteApiUrl: string; remoteModelName: string };
  test.beforeEach(async ({ request }) => {
    const s = await (await request.get('/api/settings')).json();
    standIn = { backend: s.backend, remoteApiUrl: s.remoteApiUrl, remoteModelName: s.remoteModelName };
  });
  test.afterEach(async ({ request }) => {
    await request.post('/api/backend/local-model/preset', { data: { path: null } });
    await request.post('/api/backend/local-model/context', { data: { context: 16384 } });
    const back = await request.post('/api/settings', { data: standIn });
    expect(back.ok(), `putting the stand-in backend back: ${back.status()}`).toBe(true);
  });

  test('comes back when the preset is put back to automatic', async ({ page }) => {
    const switched = await setBackend(page, 'kobold');
    expect(switched.ok(), `POST /api/settings backend=kobold: ${switched.status()}`).toBe(true);
    await openRoute(page, '/models');
    const card = page.getByTestId('local-model-card');
    await expect(card).toContainText('Set up for this computer automatically.');

    // The user's own: neither the app's default nor the preset's.
    await card.getByRole('button', { name: '65,536', exact: true }).click();
    await expect.poll(() => savedContext(page)).toBe(65536);

    const presets = page.getByLabel('Chat uses');
    await presets.selectOption({ label: 'Long chats — 32k chat · fitted to the card · smart cache off' });
    await expect(card).toContainText('Uses your preset “Long chats”.');
    await expect.poll(() => savedContext(page)).toBe(32768);

    await presets.selectOption({ label: "The app's own settings (automatic)" });
    await expect(card).toContainText('Set up for this computer automatically.');
    await expect.poll(() => savedContext(page)).toBe(65536);

    // Settings shows it, unlocked.
    await openRoute(page, '/settings');
    const slider = page.locator('.slider-field', { hasText: 'Context size' });
    await expect(slider.locator('input[type="range"]')).toBeEnabled();
    await expect(slider.locator('input[type="range"]')).toHaveValue('65536');
  });
});
