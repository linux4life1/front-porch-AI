// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What people actually do on the phone, end to end against the real app:
// sign in, open a character, chat, then edit / regenerate / swipe /
// continue / delete, switch conversations, and change a setting that must
// survive a reload. Replies come from the host's stand-in backend; the text
// is FPAI_REPLY.

import { readFile } from 'node:fs/promises';
import type { Locator, Page } from '@playwright/test';
import { expect, openRoute, SERIAL, test } from './support/fixtures';

const REPLY = process.env.FPAI_REPLY ?? '';

test('expression workspace keeps its own prompt and picture across tabs', async ({ page, allowHttp }) => {
  const original = await (await page.request.get('/api/image/config')).json() as {
    backend: string; localUrl: string;
  };
  // No image backend runs in this sandbox. Exercise preparation against the
  // real app; generation and import remain covered by the Flutter pack journey.
  allowHttp((url, status) => status === 404 && /\/api\/image\/expression-pack\/source/.test(url));
  try {
    const configured = await page.request.post('/api/image/config', {
      data: { backend: 'a1111', localUrl: 'http://127.0.0.1:9', currentPassword: process.env.FPAI_PASSWORD },
    });
    expect(configured.ok()).toBe(true);
    await openRoute(page, '/models');
    const panel = page.locator('#studio-pack-panel');
    await page.getByRole('tab', { name: 'Expression pack', exact: true }).click();
    await panel.getByLabel('Character', { exact: true }).selectOption({ label: 'Porch Tester' });
    await panel.getByLabel('Image prompt', { exact: true }).fill('A deliberate pack portrait');
    await panel.getByLabel('Pack picture file').setInputFiles({
      name: 'pack-source.png', mimeType: 'image/png',
      buffer: Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=', 'base64'),
    });
    await expect(panel).toContainText('Source: pack-source.png');
    await expect(panel.getByRole('button', { name: 'Start pack', exact: true })).toBeEnabled();
    await page.getByRole('tab', { name: 'Create', exact: true }).click();
    await expect(panel).toBeHidden();
    await page.getByRole('tab', { name: 'Edit', exact: true }).click();
    await page.getByRole('tab', { name: 'Expression pack', exact: true }).click();
    await expect(panel.getByLabel('Image prompt', { exact: true })).toHaveValue('A deliberate pack portrait');
    await expect(panel).toContainText('Source: pack-source.png');
    await panel.getByRole('button', { name: 'Use character portrait', exact: true }).click();
    await expect(panel).not.toContainText('Source: pack-source.png');
    await expect(panel.getByLabel('Image prompt', { exact: true })).toHaveValue('A deliberate pack portrait');
  } finally {
    const restored = await page.request.post('/api/image/config', {
      data: { backend: original.backend, localUrl: original.localUrl, currentPassword: process.env.FPAI_PASSWORD },
    });
    expect(restored.ok()).toBe(true);
  }
});

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

test.describe.serial('a conversation', { tag: SERIAL }, () => {
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

// The AI creator's Greetings step (#370) on a character made for this test,
// so Porch Tester's greetings (which the conversation journeys read) are left
// alone; the character is deleted whatever happens. The stand-in backend
// writes every greeting as FPAI_REPLY.
test('the creator\'s Greetings step: a steered rewrite, an edit, a delete and an add are saved', async ({
  page,
}) => {
  const created = await page.request.post('/api/characters/create', {
    data: {
      name: `Greeting Journey ${test.info().project.name}`,
      firstMessage: '*The lamp turns.* "You came."',
      alternateGreetings: ['A storm on the jetty.', 'Fog over the harbor.'],
    },
  });
  expect(created.ok(), `create: ${created.status()}`).toBe(true);
  const id = String(((await created.json()) as { id: string | number }).id);
  const detail = async () =>
    (await (await page.request.get(`/api/characters/${id}/detail`)).json()) as {
      firstMessage: string;
      alternateGreetings: string[];
    };
  try {
    await openRoute(page, `/create-ai?greetings=${id}`);
    await expect(page.getByTestId('greetings-step')).toBeVisible();
    const count = page.getByTestId('greeting-count');
    await expect(count).toHaveText('2 of 5');

    // A steered rewrite of the first message is written and saved.
    const first = page.getByTestId('greeting-card-0');
    await first.getByLabel('Steer the rewrite (optional)').fill('start at the harbor at dawn');
    await first.getByRole('button', { name: 'Regenerate' }).click();
    await expect(first.getByLabel('First message text')).toHaveValue(REPLY, { timeout: 60_000 });
    await expect.poll(async () => (await detail()).firstMessage).toBe(REPLY);

    // An alternate edited in place is saved once typing pauses.
    await page.getByTestId('greeting-card-1').getByLabel('Alternate 1 text').fill('A calm morning on the jetty.');
    await expect.poll(async () => (await detail()).alternateGreetings[0]).toBe('A calm morning on the jetty.');

    // Delete takes alternate 2 off the card.
    await page.getByTestId('greeting-card-2').getByRole('button', { name: 'Delete alternate 2' }).click();
    await expect(count).toHaveText('1 of 5');
    await expect.poll(async () => (await detail()).alternateGreetings).toEqual(['A calm morning on the jetty.']);

    // Add another writes a new one straight away.
    await page.getByRole('button', { name: 'Add another greeting' }).click();
    await expect(count).toHaveText('2 of 5', { timeout: 60_000 });
    await expect(page.getByTestId('greeting-card-2').getByLabel('Alternate 2 text')).toHaveValue(REPLY);
    await expect
      .poll(async () => (await detail()).alternateGreetings)
      .toEqual(['A calm morning on the jetty.', REPLY]);

    await page.getByRole('button', { name: 'Open in editor' }).click();
    await expect(page).toHaveURL(new RegExp(`/edit/${id}$`));
  } finally {
    const gone = await page.request.post(`/api/characters/${id}/delete`);
    expect(gone.ok(), `deleting the journey character: ${gone.status()}`).toBe(true);
  }
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

// Issue #348: two selected characters leave as one .porchpack, and the same
// file brought back is skipped by name, because the library still has them.
// Export opens each character's chats to pack them and then reopens the
// chat that was open, so the journeys after this one find it unchanged.
test('export two characters as one .porchpack; importing it back skips both by name', async ({ page }) => {
  await openRoute(page, '/');
  await page.getByRole('button', { name: '☑ Select' }).click();
  for (const name of ['Porch Tester', 'Second Guest']) {
    await page.locator('.lib-card', { hasText: name }).locator('.lib-open').click();
  }
  const bar = page.locator('.selection-bar');
  await expect(bar).toContainText('2 selected');

  const download = page.waitForEvent('download');
  await bar.getByRole('button', { name: '⬇ Export' }).click();
  const file = await download;
  expect(file.suggestedFilename()).toBe('Front Porch characters (2).porchpack');
  await expect(bar).toHaveCount(0);
  const notice = page.getByTestId('porch-notice');
  await expect(notice).toHaveText('Saved 2 characters to Front Porch characters (2).porchpack.');

  await page.getByTestId('porch-import-input').setInputFiles({
    name: file.suggestedFilename(),
    mimeType: 'application/octet-stream',
    buffer: await readFile((await file.path())!),
  });
  // A skip is news, not a failure: the notice, never the red error line.
  await expect(notice).toHaveText('Skipped 2 you already have: Porch Tester, Second Guest.');
  await expect(page.locator('p.error')).toHaveCount(0);
});

// Chat and the rest of the suite run on the stand-in backend. The Local model
// and preset cards are the local backend's (as on the desktop), so the host is
// switched to KoboldCpp for this journey only; nothing in it loads a model.
test.describe('the Local model card', () => {
  const setBackend = (page: Page, backend: 'kobold' | 'openRouter') =>
    page.request.post('/api/settings', { data: { backend } });

  // The stand-in backend as the suite set it up. Switching the backend blanks
  // the remote model name on purpose (BackendSettings.setBackendType: the
  // picker must not keep the previous host's model), so putting back the
  // backend alone leaves chat with no model.
  let standIn: { backend: string; remoteApiUrl: string; remoteModelName: string };
  test.beforeEach(async ({ request }) => {
    const s = await (await request.get('/api/settings')).json();
    standIn = { backend: s.backend, remoteApiUrl: s.remoteApiUrl, remoteModelName: s.remoteModelName };
  });

  // Whatever happened, the next spec finds the stand-in backend, working, and
  // no preset.
  test.afterEach(async ({ request }) => {
    const back = await request.post('/api/settings', { data: standIn });
    expect(back.ok(), `putting the stand-in backend back: ${back.status()}`).toBe(true);
    await request.post('/api/backend/local-model/preset', { data: { path: null } });
    const after = await (await request.get('/api/settings')).json();
    expect(after.remoteConfigured, 'the stand-in backend answers chat again').toBe(true);
  });

  test('is for a local backend only; there, a context and its verdict, then a KoboldCpp preset', async ({ page }) => {
    // The stand-in is a remote backend: no card, and no poll for one.
    const asked: string[] = [];
    page.on('request', (r) => asked.push(new URL(r.url()).pathname));
    await openRoute(page, '/models');
    await expect(page.getByRole('heading', { name: 'Models & backends' })).toBeVisible();
    await expect(page.getByTestId('local-model-card')).toHaveCount(0);
    await expect(page.getByTestId('kobold-preset-card')).toHaveCount(0);
    expect(asked).toContain('/api/backend/status');
    expect(asked).not.toContain('/api/backend/local-model');

    // The host switches to KoboldCpp (seeded by browser_test.dart with a local
    // model and one preset): the cards are there.
    const switched = await setBackend(page, 'kobold');
    expect(switched.ok(), `POST /api/settings backend=kobold: ${switched.status()}`).toBe(true);
    await openRoute(page, '/models');
    const card = page.getByTestId('local-model-card');
    await expect(card).toContainText('Set up for this computer automatically.');
    const verdict = page.getByTestId('local-model-verdict');

    // The speed test, in auto mode. The host refuses it until the model runs
    // (_speedTestWhyNot, lib/services/llm_provider.speed_test.dart), and the
    // model seeded here is only a header (e2e_local_model.dart): the button
    // is there, greyed, with the host's reason under it.
    const speedTest = card.getByTestId('speed-test-button');
    await expect(speedTest).toHaveText('Find the fastest settings for this computer');
    await expect(speedTest).toBeDisabled();
    await expect(card.getByTestId('speed-test-unavailable')).toHaveText('Start the model first, then run the test.');

    // Nothing below 16,384 is offered (the app never suggests less). A smaller
    // size set some other way is still shown as the one in use, and warned
    // about; 16,384 then puts it back.
    await expect(card.getByRole('button', { name: '16,384', exact: true })).toBeVisible();
    await expect(card.getByRole('button', { name: '8,192', exact: true })).toHaveCount(0);
    const small = await page.request.post('/api/backend/local-model/context', { data: { context: 8192 } });
    expect(small.ok(), `POST /api/backend/local-model/context 8192: ${small.status()}`).toBe(true);
    await openRoute(page, '/models');
    await expect(card.getByRole('button', { name: '8,192', exact: true })).toBeVisible();
    await expect(verdict).toContainText('Not recommended or supported.');
    await card.getByRole('button', { name: '16,384', exact: true }).click();
    await expect(verdict).toContainText('Works like now.');

    const presets = page.getByLabel('Chat uses');
    await presets.selectOption({ label: 'Long chats — 32k chat · fitted to the card · smart cache off' });
    await expect(card).toContainText('Uses your preset “Long chats”.');
    await expect(page.getByTestId('kobold-preset-card')).toContainText('lets KoboldCpp fit it to your card');
    // A preset runs its own settings: no speed test under it.
    await expect(speedTest).toHaveCount(0);

    // The preset sets the context: Settings locks the slider, in the desktop's
    // words, and the host refuses another one however it is asked.
    await openRoute(page, '/settings');
    const slider = page.locator('.slider-field', { hasText: 'Context size' });
    await expect(slider.locator('input[type="range"]')).toBeDisabled();
    await expect(
      page.getByText('Context size is controlled by the active .kcpps preset and cannot be edited here.'),
    ).toBeVisible();
    const refused = await page.request.post('/api/settings', { data: { contextSize: 8192 } });
    expect(refused.status()).toBe(400);

    // Back to automatic, as it was, and the speed test with it.
    await openRoute(page, '/models');
    await presets.selectOption({ label: "The app's own settings (automatic)" });
    await expect(card).toContainText('Set up for this computer automatically.');
    await expect(speedTest).toBeDisabled();
  });

  // The host seeds "Risky" (browser_test.dart) beside "Long chats": a list of
  // programs to run and a public tunnel. The host will not start KoboldCpp
  // from a preset like that, so the pick is refused with the reason, which
  // the phone says beside the picker. Whatever happens, afterEach puts the
  // host back on no preset.
  test('a preset that would run a program is refused beside the picker, and is not turned on', async ({
    page,
    allowHttp,
  }) => {
    // The refused pick is the host's answer (422), not a fault.
    allowHttp((url, status) => status === 422 && /\/api\/backend\/local-model\/preset$/.test(url));
    const switched = await setBackend(page, 'kobold');
    expect(switched.ok(), `POST /api/settings backend=kobold: ${switched.status()}`).toBe(true);
    await openRoute(page, '/models');
    const card = page.getByTestId('local-model-card');
    await expect(card).toContainText('Set up for this computer automatically.');

    const listed = (await (await page.request.get('/api/backend/local-model')).json()) as {
      presets: { path: string; name: string }[];
    };
    const risky = listed.presets.find((p) => p.name === 'Risky');
    expect(risky, 'the host seeded a Risky preset in the engine folder').toBeTruthy();

    const picker = page.getByLabel('Chat uses');
    await picker.selectOption(risky!.path);
    const refused = page.getByTestId('kobold-preset-card').getByTestId('preset-refused');
    await expect(refused).toBeVisible();
    await expect(refused).toContainText('mcpfile');
    await expect(refused).toContainText('remotetunnel');
    await expect(refused).toContainText('pick another preset');

    // Not turned on: the picker is where it was, the card still says
    // automatic, and the host has no preset.
    await expect(picker).toHaveValue('');
    await expect(card).toContainText('Set up for this computer automatically.');
    await expect(card).not.toContainText('Uses your preset');
    const after = (await (await page.request.get('/api/backend/local-model')).json()) as { preset: unknown };
    expect(after.preset, 'the host did not turn it on').toBeNull();

    // The host says no to whoever asks, not only to this page.
    const direct = await page.request.post('/api/backend/local-model/preset', { data: { path: risky!.path } });
    expect(direct.status()).toBe(422);
    expect(((await direct.json()) as { error: string }).error).toContain('mcpfile');

    // A preset that is fine is picked as before, and the reason goes.
    await picker.selectOption({ label: 'Long chats — 32k chat · fitted to the card · smart cache off' });
    await expect(card).toContainText('Uses your preset “Long chats”.');
    await expect(refused).toHaveCount(0);
  });
});
