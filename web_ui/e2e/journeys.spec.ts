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
    const phone = test.info().project.name.startsWith('phone');
    if (phone) {
      // env(safe-area-inset-*) is 0 in this browser. The sheet reads these
      // custom properties first, so the notch padding is real for the hit test.
      await page.addStyleTag({
        content:
          'html{--fp-safe-top:59px;--fp-safe-right:0px;--fp-safe-bottom:34px;--fp-safe-left:0px}',
      });
    }
    const mine = rows(page).filter({ hasText: 'The swing creaks as I sit down.' });
    await action(mine, 'Edit').click();
    const editor = page.getByRole('dialog', { name: 'Edit message' });
    await expect(editor).toBeVisible();
    if (phone) {
      const cancel = editor.getByRole('button', { name: 'Cancel' });
      const box = await cancel.boundingBox();
      const vp = page.viewportSize();
      if (!box || !vp) throw new Error('Edit sheet Cancel is not in the layout');
      expect(box.y).toBeGreaterThanOrEqual(0);
      expect(box.y + box.height).toBeLessThanOrEqual(vp.height);
      const hit = await page.evaluate(({ x, y }) => {
        const el = document.elementFromPoint(x, y);
        return el?.closest('button')?.textContent?.trim() ?? '';
      }, { x: box.x + box.width / 2, y: box.y + box.height / 2 });
      expect(hit).toBe('Cancel');
    }
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

test('the chat model sheet lists models you can tap, and offers providers', async ({ page }) => {
  await openPorchChat(page);
  await page.locator('.model-switch-chip').click();
  const sheet = page.getByRole('dialog', { name: 'Change model' });
  await expect(sheet.locator('.model-switch-provider select')).toBeVisible();
  await sheet.locator('.model-picker-trigger').click();
  const option = sheet.locator('.mp-option').first();
  await expect(option).toBeVisible({ timeout: 30_000 });
  // A clipped dropdown still reports "visible"; hit-test the row instead.
  const hit = await option.evaluate((el) => {
    const r = el.getBoundingClientRect();
    const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return !!at && el.contains(at);
  });
  expect(hit).toBe(true);
  await sheet.getByRole('button', { name: 'Close' }).click();
  await expect(sheet).toHaveCount(0);
});

test('a story opens in the studio: the sidebar switches screens, the Engine step offers Quick and Studio, and the reader can scroll', async ({ page }) => {
  // A fresh story each run: a draft resumes at the step it was left on, so a
  // story the other browser walked to Engine would not open on Idea below.
  const story = (await (await page.request.post('/api/stories', { data: { title: 'Journey Story' } })).json()) as { id: string; title: string };
  await openRoute(page, `/stories/${story.id}`);
  await expect(page.getByRole('heading', { name: 'Journey Story' })).toBeVisible();
  await page.getByTestId('studio-nav-director').click();
  await expect(page).toHaveURL(new RegExp(`/stories/${story.id}/director$`));
  await expect(page.getByTestId('director-directive')).toBeVisible();
  await page.getByTestId('studio-nav-lore').click();
  // exact: the "Lore & continuity" nav button also matches a loose name.
  await expect(page.getByRole('button', { name: 'Continuity', exact: true })).toBeVisible();
  await page.getByTestId('studio-nav-structure').click();
  await expect(page.getByTestId('story-continue')).toBeVisible();

  // Setup walks Idea → Cast → Shape → Engine. The idea comes first, so a story
  // that has none yet is given one before Next moves on.
  await openRoute(page, `/stories/${story.id}/setup`);
  await page.getByTestId('story-concept').fill('A lighthouse keeper finds a door in the rock.');
  for (let i = 0; i < 3; i++) await page.getByTestId('story-setup-next').click();
  await expect(page.getByTestId('story-engine-studio')).toBeVisible();
  await page.getByTestId('story-engine-quick').click();
  await expect(page.getByTestId('story-engine-quick')).toHaveClass(/\bon\b/);

  await openRoute(page, `/stories/${story.id}/read`);
  await page.getByTestId('reader-mode').getByRole('button', { name: 'Scroll' }).click();
  await expect(page.getByTestId('scroll-reader')).toBeVisible();
  await page.getByTestId('reader-mode').getByRole('button', { name: 'Book' }).click();
  await expect(page.getByTestId('scroll-reader')).toHaveCount(0);
});

test('New Story walks four steps, keeps the draft when you leave, and the shelf says where it stopped', async ({ page }) => {
  await openRoute(page, '/stories');
  await page.getByTestId('story-new').click();
  await expect(page).toHaveURL(/\/stories\/new$/);
  const step = page.getByTestId('story-setup-step');
  await expect(step).toHaveText('Idea');

  // No idea yet: Next asks for one instead of moving on (and saves nothing).
  await page.getByTestId('story-setup-next').click();
  await expect(page.getByText('Say what the story is first.')).toBeVisible();
  await expect(step).toHaveText('Idea');

  await page.getByTestId('story-title').fill('Draft Journey');
  await page.getByTestId('story-concept').fill('A courier on a drowned coast owes a smuggler forty silver.');
  await page.getByTestId('story-setup-next').click();
  await expect(step).toHaveText('Cast');
  await page.getByTestId('story-persona').click();
  await page.getByTestId('story-setup-next').click();
  await expect(step).toHaveText('Shape');
  await page.getByRole('button', { name: 'Fantasy', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Fantasy', exact: true })).toHaveClass(/\bon\b/);
  await page.getByTestId('story-setup-next').click();
  await expect(step).toHaveText('Engine');

  // Studio is the default and is recommended; Quick can be picked and shows its acts.
  await expect(page.getByTestId('story-engine-studio')).toHaveClass(/\bon\b/);
  await page.getByTestId('story-engine-quick').click();
  await expect(page.getByTestId('story-engine-quick')).toHaveClass(/\bon\b/);

  // Each job's model opens the picker, which offers the chat model and another host.
  await page.getByTestId('story-lane-prose').click();
  const sheet = page.getByTestId('story-model-picker');
  await expect(sheet).toContainText('Prose model');
  await expect(sheet.getByTestId('story-lane-chat')).toContainText('Same as chat');
  await sheet.getByTestId('story-lane-host').click();
  await expect(sheet.getByTestId('story-host-openRouter')).toBeVisible();
  await expect(sheet.getByTestId('story-lane-use')).toBeDisabled();
  await sheet.getByRole('button', { name: 'Close' }).click();
  await expect(sheet).toHaveCount(0);

  // Leaving keeps the draft; the shelf shows the step it stopped at.
  await page.getByRole('button', { name: 'Back to stories' }).click();
  await expect(page).toHaveURL(/\/stories$/);
  const book = page.locator('[data-testid^="story-book-"]', { hasText: 'Draft Journey' }).first();
  await expect(book).toContainText('Stopped at step 4 · Engine');
});
