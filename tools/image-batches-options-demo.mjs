// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
import { createRequire } from 'node:module';
import path from 'node:path';
const require = createRequire(path.resolve('web_ui/package.json'));
const { chromium, expect } = require('@playwright/test');
const [url, output] = process.argv.slice(2);
const browser = await chromium.launch({ headless: true });
let demoPage;
try {
  const context = await browser.newContext({ viewport: { width: 1200, height: 950 } });
  const login = await context.request.post(`${url}/api/auth/login`, { data: { username: 'review', password: 'synthetic-review-password' } });
  if (!login.ok()) throw new Error(`Synthetic login failed: ${login.status()}`);
  const page = await context.newPage();
  demoPage = page;
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(`${url}/#/images`);
  await page.getByRole('heading', { name: 'Images', exact: true }).waitFor();
  await page.locator('.batch-characters input').first().waitFor();
  await expect(page.getByText('Stories / Garden', {exact: true})).toBeVisible();
  await expect(page.locator('.batch-characters img')).toHaveCount(2);
  await page.locator('.batch-characters input').first().check();
  await page.getByLabel('Save destination').selectOption('expressions');
  await page.getByLabel('Expression set', {exact: true}).selectOption('full');
  await page.getByLabel('Prompt / instruction').fill('{character} in a garden');
  await page.screenshot({path: path.join(output, 'web-full-prepare.png'), fullPage: true});
  await page.locator('.batch-configuration > summary').click();
  await expect(page.locator('.fp-config-only')).toBeVisible();
  await expect(page.locator('.fp-config-only').getByRole('button', {name: 'Generate', exact: true})).toHaveCount(0);
  await page.screenshot({path: path.join(output, 'web-inline-configuration.png'), fullPage: true});
  await page.locator('.batch-configuration > summary').click();
  await page.getByRole('button', {name: 'Prompt rules · global defaults', exact: true}).click();
  const rules = page.getByRole('dialog', {name: 'Prompt rules', exact: true});
  await rules.getByLabel('Prefix', {exact: true}).fill('keep the costume');
  await expect(rules.getByRole('button', {name: 'Use for this pack', exact: true})).toBeEnabled();
  await page.screenshot({path: path.join(output, 'web-rules.png'), fullPage: true});
  await rules.getByRole('button', {name: 'Use for this pack', exact: true}).click();
  await page.locator('.batch-characters').scrollIntoViewIfNeeded();
  await page.screenshot({path: path.join(output, 'web-character-picker.png'), fullPage: true});
  const prepared = page.waitForResponse((response) => response.url().endsWith('/api/image/batches/prepare') && response.request().method() === 'POST');
  await page.getByRole('button', {name: 'Prepare for 1 characters', exact: true}).click();
  const response = await prepared;
  if (!response.ok()) throw new Error(await response.text());
  const queue = await response.json();
  const expressions = queue.jobs.filter((j) => j.kind === 'expressions');
  if (expressions.length !== 28 || !expressions.every((j) => j.prompt.startsWith('keep the costume '))) throw new Error('Full expression rules were not captured');
  await expect(page.getByRole('button', {name: 'Start 28 images', exact: true})).toBeEnabled();
  await page.getByRole('button', {name: 'Prepare', exact: true}).click();
  await page.locator('.batch-configuration > summary').click();
  await page.setViewportSize({width: 390, height: 844});
  await page.locator('.batch-configuration > summary').scrollIntoViewIfNeeded();
  await page.screenshot({path: path.join(output, 'web-mobile-configuration.png'), fullPage: true});
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  if (overflow) throw new Error('Mobile Images page overflows horizontally');
  if (errors.length) throw new Error(errors.join('\n'));
} catch (error) {
  if (demoPage) {
    console.error(await demoPage.locator('body').innerText());
    await demoPage.screenshot({ path: path.join(output, 'web-error.png'), fullPage: true });
  }
  throw error;
} finally {
  await browser.close();
}
