// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Browser suite for the web UI. Normally launched by the Flutter host
// (integration_test/web_ui/browser_test.dart), which boots the real app on a
// sandboxed library and passes the server URL + login in the environment.
// To aim it at an already-running app instead:
//   FPAI_BASE_URL=http://127.0.0.1:8085 FPAI_USER=… FPAI_PASSWORD=… npm run e2e

import { defineConfig, devices } from '@playwright/test';
import { fileURLToPath } from 'node:url';

const baseURL = process.env.FPAI_BASE_URL;
if (!baseURL) throw new Error('FPAI_BASE_URL is not set — see e2e/playwright.config.ts');

export default defineConfig({
  testDir: '.',
  outputDir: './results',
  timeout: 90_000,
  expect: { timeout: 15_000 },
  // One app, one chat engine: specs share server state, so run them in order.
  workers: 1,
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['html', { outputFolder: './report', open: 'never' }]],
  globalSetup: './support/globalSetup.ts',
  use: {
    baseURL,
    storageState: fileURLToPath(new URL('./.auth/state.json', import.meta.url)),
    trace: 'retain-on-failure',
    // The PWA's service worker would answer bundle requests itself.
    serviceWorkers: process.env.FPAI_BUNDLE_DIR ? 'block' : 'allow',
    screenshot: 'only-on-failure',
  },
  projects: [
    // WebKit on the Linux CI runner crashes now and then partway through a
    // run ("Target crashed"), on a different screen each time, Rawhide's own
    // runs included. A test whose browser died runs once more in a fresh
    // one: a real fault fails both times, and a pass on the second try is
    // reported as flaky.
    {
      name: 'phone-webkit',
      retries: process.env.CI ? 1 : 0,
      use: { ...devices['iPhone 15'] },
    },
    {
      name: 'desktop-chromium',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1280, height: 860 },
        // A test-served bundle (FPAI_BUNDLE_DIR) trips Chrome's local-network
        // check on the loopback WebSocket; the app-served bundle does not.
        launchOptions: process.env.FPAI_BUNDLE_DIR
          ? { args: ['--disable-features=LocalNetworkAccessChecks'] }
          : {},
      },
    },
  ],
});
