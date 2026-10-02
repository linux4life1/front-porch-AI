// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sign in once through the real login endpoint, seed the library through the
// web API (the same create path a phone uses — it writes a real card PNG), and
// share the session cookie with every spec. Seeding is idempotent so `npm run
// e2e` can run again and again against one held app.

import { request, type FullConfig } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CHARACTERS = [
  {
    name: 'Porch Tester',
    description: 'Exists only inside the web UI browser E2E.',
    firstMessage: 'Evening. The swing is free if you want it.',
    alternateGreetings: ['Back again? Pull up a chair.'],
  },
  {
    name: 'Second Guest',
    description: 'A second card so library, picker and switch flows have a choice.',
    firstMessage: 'Oh, hello there.',
  },
];

export default async function globalSetup(_config: FullConfig) {
  const user = process.env.FPAI_USER;
  const password = process.env.FPAI_PASSWORD;
  if (!user || !password) throw new Error('FPAI_USER / FPAI_PASSWORD are not set');
  const ctx = await request.newContext({ baseURL: process.env.FPAI_BASE_URL });
  const ok = async (what: string, res: Awaited<ReturnType<typeof ctx.get>>) => {
    if (!res.ok()) throw new Error(`${what} failed: ${res.status()} ${await res.text()}`);
    return res;
  };

  await ok('login', await ctx.post('/api/auth/login', { data: { username: user, password } }));

  const have = (await (await ok('list', await ctx.get('/api/characters'))).json()) as { id: string; name: string }[];
  for (const c of CHARACTERS) {
    if (!have.some((h) => h.name === c.name)) {
      await ok(`create ${c.name}`, await ctx.post('/api/characters/create', { data: c }));
    }
  }
  const all = (await (await ctx.get('/api/characters')).json()) as { id: string; name: string }[];
  const porch = all.find((c) => c.name === 'Porch Tester')!;
  await ok('open chat', await ctx.post('/api/chat/select', { data: { characterId: porch.id } }));

  const out = join(dirname(fileURLToPath(import.meta.url)), '..', '.auth', 'state.json');
  mkdirSync(dirname(out), { recursive: true });
  await ctx.storageState({ path: out });
  await ctx.dispose();
}
