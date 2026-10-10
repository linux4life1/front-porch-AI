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
  await page.screenshot({ path: path.join(output, 'web-prepare.png'), fullPage: true });
  await page.locator('.batch-characters input').nth(0).check();
  await page.locator('.batch-characters input').nth(1).check();
  await page.getByLabel('Prompt / instruction').fill('{character} standing beneath a tree');
  await page.getByRole('button', { name: 'Prepare for 2 characters', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Start 2 images', exact: true })).toBeEnabled();
  await page.screenshot({ path: path.join(output, 'web-queue.png'), fullPage: true });
  await page.getByRole('button', { name: 'Start 2 images', exact: true }).click();
  await expect.poll(async () => {
    const response = await context.request.get(`${url}/api/image/batches`);
    const queue = await response.json();
    return queue.jobs.filter((j) => j.state === 'review').length;
  }, { timeout: 30000 }).toBe(4);
  await page.getByRole('button', { name: 'Review', exact: true }).click();
  await expect(page.locator('.batch-results img')).toHaveCount(4);
  await page.locator('.batch-results .card').first().getByRole('button', { name: 'Keep', exact: true }).click();
  await page.getByRole('button', { name: 'Save 1 kept', exact: true }).click();
  await expect(page.locator('.batch-results .card').first()).toContainText('saved');
  await page.screenshot({ path: path.join(output, 'web-review.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole('button', { name: 'Prepare', exact: true }).click();
  await page.screenshot({ path: path.join(output, 'web-mobile.png'), fullPage: true });
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
