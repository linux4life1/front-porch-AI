// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Boons & Bogies phase 7: a bogey's boon link is the user's to fix. The
// sidebar's bogey card says what holds it back; Link / Change opens the
// picker, and the pick goes through the growth route's whitelist (`link`) to
// the host — clicked here, so a whitelist miss fails this journey. Its own
// file so the change adds a spec rather than editing journeys.spec.ts; the
// chat helpers below are the same as that file's.

import type { Page } from '@playwright/test';
import { sendLine } from './support/composer';
import { expect, openRoute, SERIAL, test } from './support/fixtures';

const REPLY = process.env.FPAI_REPLY ?? '';

const rows = (page: Page) => page.locator('.chat-messages .msg-row');
const lastRow = (page: Page) => rows(page).last();

/** The turn is fully over: Send is back and the desktop says it is idle. */
async function waitIdle(page: Page) {
  await expect(page.locator('.chat-input button.primary', { hasText: 'Send' })).toBeVisible({ timeout: 60_000 });
  await expect
    .poll(async () => {
      const s = (await (await page.request.get('/api/chat/state')).json()) as {
        isGenerating: boolean;
        isSettlingTurn?: boolean;
      };
      return !s.isGenerating && !s.isSettlingTurn;
    }, { timeout: 60_000 })
    .toBe(true);
}

async function openPorchChat(page: Page) {
  await openRoute(page, '/');
  await page.locator('.lib-card', { hasText: 'Porch Tester' }).locator('.lib-open').click();
  await expect(page.locator('.chat-view')).toBeVisible();
  await waitIdle(page);
}

async function send(page: Page, text: string) {
  await sendLine(page, text);
  await expect(rows(page).filter({ hasText: text })).toHaveCount(1);
  await waitIdle(page);
  await expect(lastRow(page).locator('.bubble.ai')).toContainText(REPLY);
}

async function openConversations(page: Page) {
  await page.locator('.chat-mgmt-btn').click();
  await page.locator('.conversations-btn').click();
}

/** Below 1024 the sidebar lives behind the header's sidebar button. */
async function openSidebar(page: Page) {
  if (!test.info().project.name.startsWith('phone')) return;
  const backdrop = page.locator('.chat-sidebar-backdrop');
  if ((await backdrop.count()) > 0 && (await backdrop.getAttribute('aria-hidden')) !== 'true') {
    return;
  }
  await page.getByRole('button', { name: 'Toggle sidebar' }).click();
}

test('a bogey\'s boon link: Link picks a boon, Change clears it', { tag: SERIAL }, async ({ page }) => {
  const before = (await (await page.request.get('/api/settings')).json()) as {
    realism?: Record<string, unknown>;
  };
  const keys = ['characterEvolutionEnabled', 'boonsBogiesEnabled', 'milestonePopupsEnabled'];
  const restore = Object.fromEntries(keys.map((k) => [k, before.realism?.[k] ?? false]));
  const on = await page.request.post('/api/settings', {
    data: { realism: Object.fromEntries(keys.map((k) => [k, true])) },
  });
  expect(on.ok(), `turning Boons & Bogies on: ${on.status()}`).toBe(true);
  const boonText = 'Pours a perfect glass of lemonade every time.';
  const flawText = 'Spills the pitcher when hurried';
  type Ring = { content: string; linkedBoon?: { content: string } | null };
  const flaw = async () =>
    ((await (await page.request.get('/api/chat/tools/growth')).json()) as { rings: Ring[] }).rings.find(
      (r) => r.content === flawText,
    );
  try {
    await openPorchChat(page);
    await openConversations(page);
    await page.getByRole('button', { name: '+ New chat' }).click();
    await waitIdle(page);
    await send(page, 'I pour us both a glass of lemonade.');
    // The stand-in's Growth pass proposes the boon; Accept keeps it.
    const check = await page.request.post('/api/chat/tools/growth', { data: { action: 'check' } });
    expect(check.ok(), `running the Growth pass: ${check.status()}`).toBe(true);
    const card = page.getByRole('dialog', { name: 'Milestone: New boon' });
    await expect(card).toBeVisible({ timeout: 60_000 });
    await card.getByRole('button', { name: 'Accept' }).click();
    await expect(card).toBeHidden();
    const plant = await page.request.post('/api/chat/tools/growth', {
      data: { action: 'plant', text: flawText, category: 'bogey' },
    });
    expect(plant.ok(), `planting the bogey: ${plant.status()}`).toBe(true);

    // The plant changed server state: load the page after it, not before.
    await page.reload();
    if (!(await page.locator('.chat-view').isVisible())) await openPorchChat(page);
    await waitIdle(page);
    await openSidebar(page);
    const bbSwitch = page.getByRole('checkbox', { name: 'Boons & Bogies' });
    await expect(bbSwitch).toBeAttached();
    // A finger taps the label, not the input under it (the phone project).
    if (!(await bbSwitch.isChecked())) await page.locator('.bb-line-head').click();
    await expect(bbSwitch).toBeChecked();

    const bogeyCard = page.locator('.growth-ring.bogey', { hasText: flawText });
    await expect(bogeyCard).toContainText('Not linked to a boon');
    await bogeyCard.getByRole('button', { name: 'Link' }).click();
    const picker = page.getByRole('dialog', { name: 'Which boon holds this back?' });
    await expect(picker).toBeVisible();
    await picker.getByRole('button', { name: /lemonade every time/ }).click();
    await expect(picker).toBeHidden();
    await expect(bogeyCard).toContainText(`Held back by ${boonText} (Novice)`);
    await expect.poll(async () => (await flaw())?.linkedBoon?.content, { message: 'link saved' }).toBe(boonText);

    await bogeyCard.getByRole('button', { name: 'Change' }).click();
    await expect(picker).toBeVisible();
    await picker.getByRole('button', { name: 'No boon' }).click();
    await expect(bogeyCard).toContainText('Not linked to a boon');
    await expect.poll(async () => (await flaw())?.linkedBoon ?? null, { message: 'link cleared' }).toBeNull();
  } finally {
    await page.request.post('/api/settings', { data: { realism: restore } });
  }
});
