// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Vitest config for the WebUI's unit tests. These exercise the pure, parity-
// critical logic (per-mode chargen payload assembly, RP text coloring, chat
// colors) with synthetic fixtures only — no real characters/chats, no running
// app, no network — so they reproduce in any clean CI checkout. jsdom provides
// localStorage/document for the chat-colors test; the React plugin transforms
// the .tsx modules under test.

import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
