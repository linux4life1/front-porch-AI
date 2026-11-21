// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { expect, openRoute, test } from './support/fixtures';
import { sendLine } from './support/composer';

test('author and edit a Bot, then reopen its direct-prose chat', async ({ page, allowHttp }, info) => {
  const name = `Rehearsal Coach ${info.project.name}`;
  const opening = 'Try a short introduction. You can start with "My name is…".';
  const next = page.getByRole('button', { name: 'Next →' });

  await openRoute(page, '/create');
  await page.getByLabel('Name').first().fill(name);
  await page.getByLabel('Card type').selectOption('bot');
  await next.click();
  await page.getByLabel('Role', { exact: true }).fill('A practical study coach.');
  await page.getByLabel('Scope', { exact: true }).fill('Practice job interview introductions.');
  await page.getByLabel('Behavior instructions', { exact: true }).fill('Offer one step at a time.');
  await next.click();
  await page.getByLabel('Opening message', { exact: true }).fill(opening);
  for (let step = 0; step < 3; step++) await next.click();
  await expect(page.locator('.review')).toContainText('Bot');
  await page.getByText('Opening preview', { exact: true }).click();
  await expect(page.locator('.review .bubble')).toContainText(opening);
  if (process.env.FPAI_BOT_CAPTURE_DIR) {
    await page.screenshot({ path: `${process.env.FPAI_BOT_CAPTURE_DIR}/${info.project.name}-bot-review.png` });
  }
  await page.getByRole('button', { name: 'Create character', exact: true }).focus();
  await page.keyboard.press('Enter');
  await page.waitForURL(/#\/chat$/);
  await expect(page.locator('.chat-messages')).toContainText(opening);

  const readChat = async () => (await page.request.get('/api/chat/state')).json() as Promise<{
    character: { id: string };
    messages: { text: string; isUser: boolean; botProse?: boolean }[];
  }>;
  const state = await readChat();
  expect(state.messages[0]).toMatchObject({ text: opening, botProse: true });
  if (process.env.FPAI_REPLY) {
    await sendLine(page, 'I’m on a quiet train. What can I do in silence?');
    await expect.poll(async () => (await readChat()).messages.at(-1)).toMatchObject({
      text: process.env.FPAI_REPLY,
      isUser: false,
      botProse: true,
    });
  }

  await openRoute(page, `/edit/${state.character.id}`);
  await expect(page.getByLabel('Card type')).toHaveValue('bot');
  await expect(page.getByLabel('Behavior instructions')).toHaveValue('Offer one step at a time.');
  if (process.env.FPAI_BOT_CAPTURE_DIR) {
    const behavior = page.getByLabel('Behavior instructions');
    await behavior.scrollIntoViewIfNeeded();
    await page.screenshot({ path: `${process.env.FPAI_BOT_CAPTURE_DIR}/${info.project.name}-bot-edit.png` });
  }
  const scope = page.getByLabel('Scope', { exact: true });
  await scope.fill('Practice silent rehearsal on a train.');
  const save = page.getByRole('button', { name: 'Save', exact: true });
  const savePath = `/api/characters/${state.character.id}`;
  allowHttp((url, status) => status === 503 && new URL(url).pathname === savePath);
  await page.route(`**${savePath}`, (route) => route.fulfill({
    status: 503,
    json: { error: 'Temporary save failure.' },
  }), { times: 1 });
  await save.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('alert')).toContainText('Temporary save failure.');
  await expect(scope).toHaveValue('Practice silent rehearsal on a train.');
  await save.focus();
  await page.keyboard.press('Enter');
  await expect(page).not.toHaveURL(/#\/edit\//);
  await openRoute(page, `/edit/${state.character.id}`);
  await expect(page.getByLabel('Scope', { exact: true })).toHaveValue('Practice silent rehearsal on a train.');
  await openRoute(page, '/chat');
  await expect(page.locator('.chat-messages')).toContainText(opening);
  expect((await readChat()).messages[0].botProse).toBe(true);
});
