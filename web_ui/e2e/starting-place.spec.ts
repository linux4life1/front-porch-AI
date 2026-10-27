// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The starting-place star, end to end against the real app: a place inside
// a world is starred from the Worlds page, the world's card names it, the
// star is stored (a fresh load still shows it and the relay reports it),
// the relay refuses a place outside the world, and a second tap clears it.

import { expect, openRoute, SERIAL, test } from './support/fixtures';

type Row = { id?: string; name: string; parentWorldId?: string | null; defaultPlaceId?: string | null };

test(
  'starting place: star a place in the Worlds menu; a new world must name one',
  { tag: SERIAL },
  async ({ page, allowHttp }) => {
    // The outside-the-world refusal is a 400 on purpose.
    allowHttp((url, status) => status === 400 && url.includes('/api/worlds/default-place'));
    const list = async () =>
      ((await (await page.request.get('/api/worlds')).json()) as { worlds: Row[] }).worlds;
    const cleanup = async () => {
      for (const w of await list()) {
        if (w.name.startsWith('Star '))
          await page.request.post(`/api/worlds/${encodeURIComponent(w.name)}/delete`);
      }
    };
    await cleanup();
    try {
      const create = (data: Record<string, unknown>) =>
        page.request.post('/api/worlds', { data: { ...data, create: true } });
      expect((await create({ name: 'Star Bletchfield', description: 'A town.', climateEnabled: true })).ok()).toBe(true);
      const townId = (await list()).find((w) => w.name === 'Star Bletchfield')!.id!;
      for (const name of ['Star Tea Rooms', 'Star Town Hall']) {
        expect((await create({ name, description: `${name}.`, climateEnabled: false, parentWorldId: townId })).ok()).toBe(true);
      }
      expect((await create({ name: 'Star Elsewhere', description: 'Far off.', climateEnabled: true })).ok()).toBe(true);
      const rows = await list();
      const teaId = rows.find((w) => w.name === 'Star Tea Rooms')!.id!;
      const elsewhereId = rows.find((w) => w.name === 'Star Elsewhere')!.id!;

      // The law is server-side: a place outside the world is refused.
      const bad = await page.request.post('/api/worlds/default-place', {
        data: { worldId: townId, placeId: elsewhereId },
      });
      expect(bad.status()).toBe(400);
      expect(((await bad.json()) as { error: string }).error).toContain('not inside this world');

      await openRoute(page, '/worlds');
      const section = page.locator('.wsg-section').filter({ hasText: 'Star Bletchfield' });
      await expect(section).toHaveCount(1);
      const startsAt = section.locator('[data-testid="world-starts-at"]');
      await expect(startsAt).toHaveCount(0);

      await section.getByRole('button', { name: 'Start chats at Star Tea Rooms', exact: true }).click();
      await expect(startsAt).toContainText('Chats start at Star Tea Rooms');
      await expect
        .poll(async () => (await list()).find((w) => w.id === townId)?.defaultPlaceId ?? null, {
          message: 'the relay reports the star',
        })
        .toBe(teaId);

      // Stored, not page state.
      await openRoute(page, '/worlds');
      const again = page.locator('.wsg-section').filter({ hasText: 'Star Bletchfield' });
      await expect(again.locator('[data-testid="world-starts-at"]')).toContainText('Star Tea Rooms');

      // Required: tapping the starred place leaves it starred.
      await again.getByRole('button', { name: 'Chats start at Star Tea Rooms', exact: true }).click();
      await expect(again.locator('[data-testid="world-starts-at"]')).toContainText('Star Tea Rooms');
      expect((await list()).find((w) => w.id === townId)?.defaultPlaceId ?? null).toBe(teaId);

      // ── A new world names its starting place in the editor ──────────────
      await page.getByRole('button', { name: '＋ New place', exact: true }).click();
      await page.locator('.world-edit label input').first().fill('Star Harbour');
      await page.getByRole('button', { name: 'Save place', exact: true }).click();
      await expect(page.locator('[data-testid="world-starting-place"] [role="alert"]')).toHaveText(
        'Name the place where chats in this world start.',
      );
      await page.getByLabel('Starting place', { exact: true }).fill('Star Quay');
      await page.getByRole('button', { name: 'Save place', exact: true }).click();
      await expect
        .poll(async () => {
          const rows = await list();
          const harbour = rows.find((w) => w.name === 'Star Harbour');
          const quay = rows.find((w) => w.name === 'Star Quay');
          return harbour != null && quay != null && quay.parentWorldId === harbour.id && harbour.defaultPlaceId === quay.id;
        }, { message: 'the world is saved with its starting place inside it, starred' })
        .toBe(true);
      await expect(
        page.locator('.wsg-section').filter({ hasText: 'Star Harbour' }).locator('[data-testid="world-starts-at"]'),
      ).toContainText('Chats start at Star Quay');
    } finally {
      await cleanup();
    }
  },
);
