// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character ↔ persona conversion on the phone, against the real app:
// a library card's "Use as persona" saves a persona (macros swapped), and
// that persona's "Make a character" opens the manual wizard and the AI
// creator pre-filled. The new personas and characters are removed after.

import type { Page } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';

type Persona = { id: string; name: string; default: boolean };

const personas = async (page: Page) =>
  ((await (await page.request.get('/api/personas')).json()) as { personas: Persona[] }).personas;

test('a character becomes a persona, and the persona starts a character both ways', async ({ page }) => {
  const run = test.info().project.name;
  const charName = `Porch Neighbour ${run}`;
  const created = await page.request.post('/api/characters/create', {
    data: {
      name: charName,
      description: '{{char}} lives next door to {{user}}.',
      personality: 'Nosy but kind.',
    },
  });
  expect(created.ok(), `create: ${created.status()}`).toBe(true);
  const charId = String(((await created.json()) as { id: string | number }).id);
  const before = await personas(page);
  const defaultBefore = before.find((p) => p.default)?.id;
  let personaId: string | undefined;
  let madeId: string | undefined;
  try {
    // ── Character → persona ────────────────────────────────────────────
    await openRoute(page, '/');
    const card = page.locator('.lib-card', { hasText: charName });
    await card.getByRole('button', { name: 'More actions' }).click();
    await page.getByRole('menuitem', { name: 'Use as persona' }).click();
    const convert = page.getByRole('dialog', { name: 'Use as persona' });
    await expect(convert.getByRole('checkbox')).toBeChecked();
    await convert.getByRole('button', { name: 'Create persona' }).click();
    await expect(page.getByTestId('persona-notice')).toContainText(`"${charName}" is now a persona`);

    const persona = (await personas(page)).find((p) => p.name === charName);
    expect(persona, 'the new persona is listed').toBeTruthy();
    personaId = persona!.id;
    const detail = (await (await page.request.get(`/api/personas/${personaId}/detail`)).json()) as {
      persona: string;
    };
    expect(detail.persona).toBe('{{user}} lives next door to {{char}}.\n\nPersonality: Nosy but kind.');

    // ── Persona → character, Manual ────────────────────────────────────
    await openRoute(page, '/settings');
    await page.getByRole('button', { name: `Make a character from ${charName}` }).click();
    const make = page.getByRole('dialog', { name: 'Make a character' });
    await make.getByRole('button', { name: 'Manual' }).click();
    await expect(page).toHaveURL(/\/create\?fromPersona=/);
    await expect(page.getByTestId('persona-seed-note')).toContainText(charName);
    const nameBox = page.locator('.wizard-body label', { hasText: 'Name' }).locator('input');
    await expect(nameBox).toHaveValue(charName);
    await expect(page.locator('.wizard-body label', { hasText: 'Description' }).locator('textarea')).toHaveValue(
      '{{char}} lives next door to {{user}}.\n\nPersonality: Nosy but kind.',
    );
    const madeName = `${charName} Again`;
    await nameBox.fill(madeName);
    for (let i = 0; i < 5; i++) await page.getByRole('button', { name: 'Next →' }).click();
    await page.getByRole('button', { name: 'Create character' }).click();
    // `/chat?opening=1` comes first; wait for the select to land so its
    // `/chat` redirect cannot pull the next navigation back.
    await expect(page).toHaveURL(/\/chat$/);
    const lib = (await (await page.request.get('/api/characters')).json()) as
      | { id: string; name: string }[]
      | { characters: { id: string; name: string }[] };
    const list = Array.isArray(lib) ? lib : lib.characters;
    madeId = list.find((c) => c.name === madeName)?.id;
    expect(madeId, 'the character made from the persona is in the library').toBeTruthy();

    // ── Persona → character, AI Assist (pre-fill only; nothing generates) ──
    await openRoute(page, '/settings');
    await page.getByRole('button', { name: `Make a character from ${charName}` }).click();
    await page.getByRole('dialog', { name: 'Make a character' }).getByRole('button', { name: 'AI Assist' }).click();
    await expect(page).toHaveURL(/\/create-ai\?fromPersona=/);
    await expect(page.getByTestId('persona-seed-note')).toContainText(charName);
    await expect(page.locator('.cg-field', { hasText: 'Name' }).locator('input')).toHaveValue(charName);
  } finally {
    if (madeId) await page.request.post(`/api/characters/${madeId}/delete`);
    if (defaultBefore) await page.request.post('/api/personas/select', { data: { id: defaultBefore } });
    if (personaId) await page.request.post(`/api/personas/${personaId}/delete`);
    const gone = await page.request.post(`/api/characters/${charId}/delete`);
    expect(gone.ok(), `deleting the journey character: ${gone.status()}`).toBe(true);
  }
});
