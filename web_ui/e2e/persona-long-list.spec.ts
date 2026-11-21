// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A long persona list on the phone and the desktop, against the real app.
// The seeded personas are removed and the default and chat persona put back
// after.

import { expect, openRoute, test } from './support/fixtures';

// A phone report with ~30 personas: "+ New Persona" opened its form under the
// whole grid (it looked like nothing happened), and the chat's "Speak as…"
// list ran off the screen with no way to reach the rest. The form now
// replaces the list like the desktop page, and the switcher's list scrolls
// like the desktop dialog's.
test('a long persona list: New Persona opens in view and saves, and Speak as… reaches the last one', async ({ page }) => {
  type Persona = { id: string; name: string; active: boolean; default: boolean };
  const list = async () =>
    ((await (await page.request.get('/api/personas')).json()) as { personas: Persona[] }).personas;
  const run = test.info().project.name;
  const before = await list();
  const defaultBefore = before.find((p) => p.default)!.id;
  const activeBefore = before.find((p) => p.active)!.id;
  const seeded = Array.from({ length: 30 }, (_, i) => `Long List ${run} ${String(i).padStart(2, '0')}`);
  const newcomer = `Porch Newcomer ${run}`;
  try {
    for (const name of seeded) {
      const made = await page.request.post('/api/personas/create', { data: { name, persona: 'Seeded.' } });
      expect(made.ok(), `seeding ${name}: ${made.status()}`).toBe(true);
    }
    // Creating moves the default; put it back before any chat reads it.
    await page.request.post('/api/personas/select', { data: { id: defaultBefore } });

    // ── The page: from the bottom of a long grid, the form opens in view ──
    await openRoute(page, '/persona');
    const lastCard = page.locator('.persona-grid li', { hasText: seeded[29] });
    await lastCard.scrollIntoViewIfNeeded();
    await page.getByRole('button', { name: '+ New Persona' }).click();
    await expect(page.getByRole('heading', { name: 'Create Persona' })).toBeInViewport();
    await expect(page.locator('.persona-grid')).toHaveCount(0);
    const form = page.locator('.persona-edit');
    await form.getByLabel('Name', { exact: true }).fill(newcomer);
    await form.getByLabel('Persona Text (injected into AI context)').fill('Just moved in next door.');
    await form.getByRole('button', { name: 'Save Persona' }).click();
    await expect(page.getByTestId('persona-save-notice')).toHaveText('Persona saved successfully');
    await expect(page.locator('.persona-grid li', { hasText: newcomer })).toHaveCount(1);
    await page.request.post('/api/personas/select', { data: { id: defaultBefore } });

    // ── The chat: the switcher's list scrolls to its last persona ─────────
    await openRoute(page, '/');
    await page.locator('.lib-card', { hasText: 'Porch Tester' }).locator('.lib-open').click();
    await expect(page.locator('.chat-view')).toBeVisible();
    await expect(page.locator('.chat-input button.primary', { hasText: 'Send' })).toBeVisible({ timeout: 60_000 });
    await page.getByRole('button', { name: 'Persona', exact: true }).click();
    const speakAs = page.getByRole('dialog', { name: 'Speak as' });
    const last = speakAs.locator('.persona-list li').last();
    await last.scrollIntoViewIfNeeded();
    await expect(last).toBeInViewport();
    await expect(speakAs.getByRole('button', { name: 'Close' })).toBeInViewport();
    await speakAs.getByRole('button', { name: 'Close' }).click();
    await expect(speakAs).toHaveCount(0);
  } finally {
    await page.request.post('/api/personas/select', { data: { id: defaultBefore } });
    await page.request.post('/api/chat/persona', { data: { id: activeBefore } });
    for (const p of await list()) {
      if (seeded.includes(p.name) || p.name === newcomer) {
        const gone = await page.request.post(`/api/personas/${p.id}/delete`);
        expect(gone.ok(), `removing ${p.name}: ${gone.status()}`).toBe(true);
      }
    }
  }
});
