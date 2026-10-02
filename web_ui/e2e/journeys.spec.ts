// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What people actually do on the phone, end to end against the real app:
// sign in, open a character, chat, then edit / regenerate / swipe /
// continue / delete, switch conversations, and change a setting that must
// survive a reload. Replies come from the host's stand-in backend; the text
// is FPAI_REPLY.

import type { Locator, Page } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';

const REPLY = process.env.FPAI_REPLY ?? '';

const rows = (page: Page) => page.locator('.chat-messages .msg-row');
const lastRow = (page: Page) => rows(page).last();
const action = (row: Locator, title: string) => row.locator(`.msg-actions button[title="${title}"]`);

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
  const box = page.locator('textarea.composer-input');
  await box.fill(text);
  await box.press('Enter');
  await expect(rows(page).filter({ hasText: text })).toHaveCount(1);
  await waitIdle(page);
  await expect(lastRow(page).locator('.bubble.ai')).toContainText(REPLY);
}

test.describe('signing in', () => {
  test.use({ storageState: { cookies: [], origins: [] } });

  test('a wrong password says so; the right one opens the library', async ({ page, allowHttp }) => {
    allowHttp((url, status) => status === 401 && /\/api\/(auth\/login|auth\/state|chat\/state)/.test(url));
    await page.goto('/');
    await page.getByLabel('Username').fill(process.env.FPAI_USER!);
    await page.getByLabel('Password').fill('not-the-password');
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.locator('.auth-card .error')).toBeVisible();

    await page.getByLabel('Password').fill(process.env.FPAI_PASSWORD!);
    await page.getByRole('button', { name: 'Sign in' }).click();
    await expect(page.locator('.lib-card', { hasText: 'Porch Tester' })).toBeVisible();
  });
});

test.describe.serial('a conversation', () => {
  test('open a character, start a fresh chat, and get a reply', async ({ page }) => {
    await openPorchChat(page);
    await page.locator('.conversations-btn').click();
    await page.getByRole('button', { name: '+ New chat' }).click();
    await waitIdle(page);
    await expect(rows(page)).toHaveCount(1); // just the greeting
    await send(page, 'The swing creaks as I sit down.');
  });

  test('edit a message and save it (#330)', async ({ page }) => {
    await openPorchChat(page);
    const mine = rows(page).filter({ hasText: 'The swing creaks as I sit down.' });
    await action(mine, 'Edit').click();
    const editor = page.getByRole('dialog', { name: 'Edit message' });
    await expect(editor).toBeVisible();
    await editor.locator('textarea.msg-edit-body').fill('I sit on the porch swing instead.');
    await editor.getByRole('button', { name: 'Save' }).click();
    await expect(editor).toBeHidden();
    await expect(rows(page).filter({ hasText: 'I sit on the porch swing instead.' })).toHaveCount(1);

    // Cancel leaves the message alone.
    await action(rows(page).filter({ hasText: 'porch swing instead' }), 'Edit').click();
    await expect(editor).toBeVisible();
    await editor.getByRole('button', { name: 'Cancel' }).click();
    await expect(editor).toBeHidden();
  });

  test('regenerate with a note, then swipe between the two takes', async ({ page }) => {
    await openPorchChat(page);
    await action(lastRow(page), 'Regenerate').click();
    const dialog = page.getByTestId('regen-critique-dialog');
    await dialog.getByTestId('regen-critique-field').fill('a little warmer');
    await dialog.getByRole('button', { name: 'Regenerate' }).click();
    await waitIdle(page);
    const count = lastRow(page).locator('.swipe-count');
    await expect(count).toHaveText('2/2');
    await action(lastRow(page), 'Previous').click();
    await waitIdle(page);
    await expect(count).toHaveText('1/2');
  });

  test('continue adds to the last reply', async ({ page }) => {
    await openPorchChat(page);
    const bubble = lastRow(page).locator('.bubble.ai');
    const before = (await bubble.innerText()).length;
    await action(lastRow(page), 'Continue').click();
    await waitIdle(page);
    await expect.poll(async () => (await bubble.innerText()).length).toBeGreaterThan(before);
  });

  test('delete the last reply after confirming', async ({ page, acceptConfirms }) => {
    await openPorchChat(page);
    const n = await rows(page).count();
    acceptConfirms(true);
    await action(lastRow(page), 'Delete').click();
    await expect(rows(page)).toHaveCount(n - 1);
  });

  test('switch to a new chat and back again', async ({ page }) => {
    await openPorchChat(page);
    await page.locator('.conversations-btn').click();
    await page.getByRole('button', { name: '+ New chat' }).click();
    await waitIdle(page);
    await expect(rows(page)).toHaveCount(1);

    await page.locator('.conversations-btn').click();
    await page.locator('.conv-item:not(.active)').filter({ hasText: /msgs/ }).first().click();
    await waitIdle(page);
    await expect(rows(page).filter({ hasText: 'I sit on the porch swing instead.' })).toHaveCount(1);
  });
});

test('a setting survives a reload', async ({ page }) => {
  await openRoute(page, '/settings');
  const toggle = page.getByLabel('Follow streaming replies');
  const was = await toggle.isChecked();
  await toggle.setChecked(!was);
  await page.waitForLoadState('networkidle');
  await page.reload();
  await expect(page.getByLabel('Follow streaming replies')).toBeChecked({ checked: !was });
  await page.getByLabel('Follow streaming replies').setChecked(was);
  await page.waitForLoadState('networkidle');
});

test('edit a character, save, and nothing else on the card is lost', async ({ page }) => {
  const list = (await (await page.request.get('/api/characters')).json()) as { id: string; name: string }[];
  const id = list.find((c) => c.name === 'Porch Tester')!.id;
  const detail = async () =>
    (await (await page.request.get(`/api/characters/${id}/detail`)).json()) as {
      tags: string[];
      alternateGreetings?: string[];
      firstMessage: string;
    };
  const before = await detail();
  const tags = `porch, journey-${test.info().project.name}`;

  await openRoute(page, `/edit/${id}`);
  await page.getByLabel('Tags (comma-separated)').fill(tags);
  await page.getByRole('button', { name: 'Save character' }).click();
  await expect(page.getByRole('button', { name: /Saving/ })).toHaveCount(0);

  await openRoute(page, `/edit/${id}`);
  await expect(page.getByLabel('Tags (comma-separated)')).toHaveValue(tags);
  const after = await detail();
  expect(after.alternateGreetings).toEqual(before.alternateGreetings);
  expect(after.firstMessage).toBe(before.firstMessage);
});
