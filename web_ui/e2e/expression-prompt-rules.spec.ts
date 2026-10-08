// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { expect, openRoute, test } from './support/fixtures';
import type { PromptRules } from '../src/components/models/studio/packApi';

test('pack editor saves defaults explicitly and keeps cancelled local wording', async ({ page }) => {
  const path = '/api/image/expression-pack/settings';
  const original = await (await page.request.get(path)).json() as PromptRules;
  try {
    await openRoute(page, '/models');
    // The workspace's mode switch is a tab list.
    await page.getByRole('tab', { name: 'Expression pack', exact: true }).click();
    await page.getByRole('button', { name: 'Prompt rules...', exact: true }).click();
    const editor = page.getByRole('dialog', { name: 'Prompt rules' });
    await expect(editor.getByLabel('Prefix')).toHaveValue(original.prefix);
    await editor.getByLabel('Prefix').fill('Controlled expression framing');
    await editor.getByRole('button', { name: 'Save as global defaults' }).click();
    await expect(editor).toContainText('Global defaults saved.');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    await page.getByRole('button', { name: 'Prompt rules...', exact: true }).click();
    await expect(editor.getByLabel('Prefix')).toHaveValue(original.prefix);
    await editor.getByLabel('Prefix').fill('Local expression framing');
    await editor.getByRole('button', { name: 'Use for this pack' }).click();
    await expect(editor).not.toBeVisible();
    await page.getByRole('button', { name: 'Prompt rules...', exact: true }).click();
    await expect(editor.getByLabel('Prefix')).toHaveValue('Local expression framing');
    await editor.getByRole('button', { name: 'Cancel', exact: true }).click();
    const saved = await (await page.request.get(path)).json() as PromptRules;
    expect(saved.prefix).toBe('Controlled expression framing');
  } finally {
    const restored = await page.request.post(path, { data: { promptRules: original } });
    expect(restored.ok()).toBe(true);
  }
});
