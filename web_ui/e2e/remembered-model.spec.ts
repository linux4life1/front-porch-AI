// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Each remote backend remembers the model last used on it. Switching away
// and back brings that model back, on the host and in Settings, instead of
// an empty picker. Against the real app; nothing here sends a chat.

import { expect, openRoute, test } from './support/fixtures';

const NANO = 'https://nano-gpt.com/api/v1';
const NANO_MODEL = 'journey/remembered-on-nano';

interface Snapshot {
  backend: string;
  remoteApiUrl: string;
  remoteModelName: string;
  remoteApiModels?: Record<string, string>;
}

test.describe('the model last used on each backend', () => {
  let standIn: { backend: string; remoteApiUrl: string; remoteModelName: string };
  test.beforeEach(async ({ request }) => {
    const s = (await (await request.get('/api/settings')).json()) as Snapshot;
    standIn = { backend: s.backend, remoteApiUrl: s.remoteApiUrl, remoteModelName: s.remoteModelName };
  });
  test.afterEach(async ({ request }) => {
    const back = await request.post('/api/settings', {
      data: { ...standIn, currentPassword: process.env.FPAI_PASSWORD },
    });
    expect(back.ok(), `putting the stand-in backend back: ${back.status()}`).toBe(true);
  });

  test('comes back when you switch to that backend again', async ({ page }) => {
    const post = (data: Record<string, unknown>) =>
      page.request.post('/api/settings', {
        data: { ...data, currentPassword: process.env.FPAI_PASSWORD },
      });

    // A model picked on Nano-GPT.
    const toNano = await post({ backend: 'openRouter', remoteApiUrl: NANO, remoteModelName: NANO_MODEL });
    expect(toNano.ok(), `switching to Nano-GPT: ${toNano.status()}`).toBe(true);

    // Back to the stand-in with no model named: the host restores its own.
    const back = await post({ backend: standIn.backend, remoteApiUrl: standIn.remoteApiUrl });
    expect(back.ok(), `switching back: ${back.status()}`).toBe(true);
    const after = (await back.json()) as Snapshot;
    expect(after.remoteModelName).toBe(standIn.remoteModelName);
    expect(Object.values(after.remoteApiModels ?? {})).toContain(NANO_MODEL);

    // Settings: choosing Nano-GPT shows its model again before any save.
    await openRoute(page, '/settings');
    const card = page.getByTestId('chat-speech-card');
    await card.getByLabel('Backend').selectOption({ label: 'Nano-GPT' });
    await expect(card.locator('.model-picker-trigger')).toContainText(NANO_MODEL);
  });
});
