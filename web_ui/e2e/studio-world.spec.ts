// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The studio's world screens, end to end against the real app: Director, Cast,
// Relationships, Lore & continuity and the Run log. Nothing here needs a model:
// each story is seeded by saving a project, the screens are driven the way a
// finger would, and every assertion reads the story back from the server.

import type { Page } from '@playwright/test';
import { expect, openRoute, test } from './support/fixtures';

type Json = Record<string, unknown>;

const wren = {
  name: 'Wren', role: 'Protagonist', description: 'Keeper of the light.', desire: 'To be waited for.', flaw: 'Nobody will stay.',
  interview: 'Wren looks away and talks about the light.', voice_sample: 'Short, dry.', details: { secret: 'She reads the undelivered letters.' },
};
const dov = { name: 'Dov Marsh', role: 'Supporting', description: 'The postman.', desire: 'To matter.', flaw: 'Avoids goodbyes.', details: {} };

const SEED: Json = {
  engine_mode: 'studio',
  cast: [wren, dov],
  relationships: [{
    from: 'Wren', to: 'Dov Marsh', feeling: 'Fond', note: 'old friends', subtext: 'He knows about the letters.', trust: 7,
    history: [{ scene_id: '', from: '—', to: 'Fond', reason: 'Where they start.' }],
  }],
  continuity: [{ category: 'Object', key: 'The notebook', value: 'Holds the word "stay".', entity: 'Wren', scene_id: '' }],
  lore: [{ topic: 'The Flicker', detail: 'The lamp on the point.', related_to: ['file:island.md'], valid_from_act: 1, valid_from_scene: 1 }],
  acts: [{ number: 1, title: 'Act I', description: '', focus_thread_ids: [], knots: [] }],
  sequences: [{ number: 1, act: 1, title: 'The Light', summary: 'Wren keeps the lamp.' }],
  scenes: { 0: [{ number: 1, id: 'scene-one', title: 'Reading the Flicker', description: '', location: '', cast_names: ['Wren'], valence: 0, sequence: 1, summary: 'Wren reads the lamp.' }] },
  director_plan: {
    directive: 'Make Dov secretly the one who put out the light.', evaluation: 'One change to the story.', scope: 'local',
    consistency_notes: '', review: 'consistent', created_at: new Date().toISOString(),
    actions: [{
      type: 'MODIFY_STORY', scene_id: '', beat: 0, sequence: 0, act: 0, summary: 'Dov is the one who put out the light.',
      details: {}, enabled: true, locked: false, result: '',
    }],
  },
};

/** A new story with [SEED] (and [patch]) saved onto it. */
async function seededStory(page: Page, title: string, patch: Json = {}): Promise<string> {
  const created = (await (await page.request.post('/api/stories', { data: { title } })).json()) as { id: string };
  const project = (await (await page.request.get(`/api/stories/${created.id}`)).json()) as Json;
  const saved = await page.request.post(`/api/stories/${created.id}`, { data: { ...project, ...SEED, ...patch } });
  expect(saved.ok()).toBe(true);
  return created.id;
}

/** The slices of a stored story these journeys read back. */
interface Stored {
  director_draft?: string;
  director_protect?: boolean;
  director_plan?: { actions: { enabled: boolean }[] } | null;
  cast: { name: string; flaw?: string; interview?: string }[];
  relationships: { from: string; to: string; feeling: string; note: string; trust: number; history: Json[] }[];
  continuity: { key: string; retired_scene_id?: string }[];
  lore: Json[];
}

const read = async (page: Page, id: string) => (await (await page.request.get(`/api/stories/${id}`)).json()) as Stored;

const dialog = (page: Page, name: string) => page.getByRole('dialog', { name });

test('Director remembers the box and the protect switch, ticks a change and discards the plan in the page', async ({ page }) => {
  const id = await seededStory(page, 'World Director Journey');
  await openRoute(page, `/stories/${id}/director`);

  // An empty box cannot be planned; the story has acts, so the "needs a structure" hint stays away.
  await expect(page.getByTestId('director-plan')).toBeDisabled();
  await expect(page.getByText('The Director needs a structure to work on. Build the story bible and acts first.')).toHaveCount(0);

  const card = page.getByTestId('director-plan-card');
  await expect(card).toContainText('Proposed plan · 1 change · local');
  await expect(card).toContainText('Reviewed: consistent');
  await expect(page.getByTestId('director-apply')).toHaveText('Apply 1 change');

  // The box is kept when the focus leaves it, and when the section does.
  await page.getByTestId('director-directive').fill('Dov hides the letters instead.');
  await card.getByText('Proposed plan').click();
  await expect.poll(async () => (await read(page, id)).director_draft).toBe('Dov hides the letters instead.');
  await page.getByTestId('director-directive').fill('Typed, then left for another section.');
  await page.getByTestId('studio-nav-cast').click();
  await expect.poll(async () => (await read(page, id)).director_draft).toBe('Typed, then left for another section.');
  await page.getByTestId('studio-nav-director').click();
  await expect(page.getByTestId('director-directive')).toHaveValue('Typed, then left for another section.');

  // The protect switch is saved on the story; a ticked change is a toggle on the server.
  await page.getByTestId('director-protect').click();
  await expect.poll(async () => (await read(page, id)).director_protect).toBe(false);
  await page.getByTestId('director-action-0').getByRole('checkbox').click();
  await expect(page.getByTestId('director-apply')).toHaveText('Apply 0 changes');
  await expect(page.getByTestId('director-apply')).toBeDisabled();
  await expect.poll(async () => (await read(page, id)).director_plan?.actions[0].enabled).toBe(false);
  // The box survived both server edits (they merge into the stored story).
  expect((await read(page, id)).director_draft).toBe('Typed, then left for another section.');

  // Discard asks first, and says nothing in the story changes.
  await page.getByTestId('director-discard').click();
  const confirm = dialog(page, 'Discard this plan?');
  await expect(confirm).toContainText('The proposed changes are dropped. Nothing in the story changes.');
  await confirm.getByRole('button', { name: 'Cancel' }).click();
  await expect(card).toHaveCount(1);
  await page.getByTestId('director-discard').click();
  await page.getByTestId('story-confirm').click();
  await expect(card).toHaveCount(0);
  await expect.poll(async () => (await read(page, id)).director_plan ?? null).toBeNull();
});

test('Cast adds, edits and removes a character, and removing takes their relationships with them', async ({ page }) => {
  const id = await seededStory(page, 'World Cast Journey');
  await openRoute(page, `/stories/${id}/cast`);
  await expect(page.getByText('2 characters')).toBeVisible();
  await expect(page.getByTestId('cast-Wren')).toContainText('From their interview');
  await expect(page.getByTestId('cast-Wren')).toContainText('Secret: She reads the undelivered letters.');
  // Dov has no interview yet: the card offers one, by first name.
  await expect(page.getByTestId('cast-interview-Dov Marsh')).toHaveText('Interview Dov');

  await page.getByTestId('cast-add').click();
  const add = dialog(page, 'Add character');
  await expect(add.getByRole('button', { name: 'Add', exact: true })).toBeDisabled();
  await add.getByTestId('cast-edit-name').fill('  Mira ');
  await add.getByTestId('cast-edit-role').fill('Mentor');
  await add.getByTestId('cast-edit-flaw').fill('pride');
  await add.getByRole('button', { name: 'Add', exact: true }).click();
  await expect(page.getByTestId('cast-Mira')).toBeVisible();
  await expect.poll(async () => (await read(page, id)).cast.map((c) => c.name)).toEqual(['Wren', 'Dov Marsh', 'Mira']);
  expect((await read(page, id)).cast[2]).toMatchObject({ name: 'Mira', role: 'Mentor', flaw: 'pride' });

  await page.getByTestId('cast-menu-Wren').click();
  await page.getByRole('menuitem', { name: 'Edit…' }).click();
  const edit = dialog(page, 'Edit Wren');
  await expect(edit.getByTestId('cast-edit-flaw')).toHaveValue('Nobody will stay.');
  await edit.getByTestId('cast-edit-flaw').fill('Waits too long.');
  await edit.getByRole('button', { name: 'Save' }).click();
  await expect.poll(async () => (await read(page, id)).cast[0].flaw).toBe('Waits too long.');
  expect((await read(page, id)).cast[0].interview).toBe(wren.interview);

  await page.getByRole('button', { name: 'Read the whole interview' }).click();
  await expect(dialog(page, 'Wren, interviewed')).toContainText('Wren looks away and talks about the light.');
  await dialog(page, 'Wren, interviewed').getByRole('button', { name: 'Close' }).click();

  await page.getByTestId('cast-menu-Dov Marsh').click();
  await page.getByRole('menuitem', { name: 'Remove from cast…' }).click();
  const remove = dialog(page, 'Remove Dov Marsh from the cast?');
  await expect(remove).toContainText('Their dossier, interview and relationships are removed. Scenes already written keep their text.');
  await remove.getByRole('button', { name: 'Remove' }).click();
  await expect(page.getByTestId('cast-Dov Marsh')).toHaveCount(0);
  await expect.poll(async () => (await read(page, id)).cast.map((c) => c.name)).toEqual(['Wren', 'Mira']);
  expect((await read(page, id)).relationships).toEqual([]);
});

test('Relationships edit a pair by hand, add one and remove one', async ({ page }) => {
  const id = await seededStory(page, 'World Relationships Journey');
  await openRoute(page, `/stories/${id}/relationships`);
  await expect(page.getByText('Nothing recorded yet')).toBeVisible();
  await expect(page.getByTestId('rel-detail')).toContainText('Wren → Dov Marsh');
  await expect(page.getByTestId('rel-detail')).toContainText('trust 7/10');
  await expect(page.getByTestId('rel-detail')).toContainText('Unspoken: He knows about the letters.');

  // Editing the feeling by hand writes a history step; a note left empty is not cleared.
  await page.getByTestId('rel-edit').click();
  const edit = dialog(page, 'Wren → Dov Marsh');
  await edit.getByTestId('rel-feeling').fill('Resentful');
  await edit.getByTestId('rel-note').fill('');
  await edit.getByTestId('rel-trust').fill('2');
  await edit.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByTestId('rel-detail')).toContainText('trust 2/10');
  const pair = async () => (await read(page, id)).relationships[0];
  await expect.poll(async () => (await pair()).feeling).toBe('Resentful');
  expect(await pair()).toMatchObject({ trust: 2, note: 'old friends' });
  expect((await pair()).history[1]).toEqual({ scene_id: '', from: 'Fond', to: 'Resentful', reason: 'Edited by hand.' });

  // Add the pair the other way round: Dov sees Wren.
  await page.getByTestId('rel-add').click();
  const add = dialog(page, 'Add pair');
  await expect(add.getByRole('button', { name: 'Add', exact: true })).toBeDisabled();
  await add.getByRole('button', { name: 'Dov Marsh', exact: true }).first().click();
  await add.getByTestId('rel-feeling').fill('Wary');
  await add.getByRole('button', { name: 'Add', exact: true }).click();
  await expect.poll(async () => (await read(page, id)).relationships.length).toBe(2);
  expect((await read(page, id)).relationships[1]).toMatchObject({ from: 'Dov Marsh', to: 'Wren', feeling: 'Wary', trust: 5 });
  await expect(page.getByTestId('rel-detail')).toContainText('Dov Marsh → Wren');

  await page.getByTestId('rel-menu').click();
  await page.getByRole('menuitem', { name: 'Remove pair…' }).click();
  const remove = dialog(page, 'Remove Dov Marsh → Wren?');
  await expect(remove).toContainText('The engine may record it again after the next scene.');
  await remove.getByRole('button', { name: 'Remove' }).click();
  await expect.poll(async () => (await read(page, id)).relationships.length).toBe(1);
});

test('Lore & continuity adds, retires and forgets a fact, removes a lore entry, and reads the story so far', async ({ page }) => {
  const id = await seededStory(page, 'World Lore Journey');
  await openRoute(page, `/stories/${id}/lore`);
  await expect(page.getByTestId('lore-subtitle')).toHaveText('1 fact · 1 lore entry · 1 file');
  await expect(page.getByTestId('lore-facts')).toContainText('The notebook');
  await expect(page.getByTestId('lore-facts')).toContainText('always');

  await page.getByTestId('lore-add-fact').click();
  const add = dialog(page, 'Add fact');
  await expect(add.getByRole('button', { name: 'Add', exact: true })).toBeDisabled();
  await add.getByRole('button', { name: 'Place', exact: true }).click();
  await add.getByTestId('fact-key').fill('Inn roof');
  await add.getByTestId('fact-value').fill('reached by the kitchen ladder');
  await add.getByRole('button', { name: 'Add', exact: true }).click();
  await expect.poll(async () => (await read(page, id)).continuity.length).toBe(2);
  expect((await read(page, id)).continuity[1]).toMatchObject({ category: 'Place', key: 'Inn roof', value: 'reached by the kitchen ladder', scene_id: '' });

  await page.getByTestId('fact-menu-Inn roof').click();
  await page.getByRole('menuitem', { name: 'Retire from scene…' }).click();
  const retire = dialog(page, 'Retire “Inn roof” from which scene?');
  await retire.getByRole('button', { name: /Reading the Flicker/ }).click();
  await expect.poll(async () => (await read(page, id)).continuity[1].retired_scene_id).toBe('scene-one');
  await expect(page.getByTestId('lore-facts')).toContainText('Retired');
  await page.getByTestId('fact-menu-Inn roof').click();
  await expect(page.getByRole('menuitem', { name: 'Retire from scene…' })).toHaveCount(0);
  await page.keyboard.press('Escape');

  await page.getByTestId('fact-menu-The notebook').click();
  await page.getByRole('menuitem', { name: 'Forget…' }).click();
  const forget = dialog(page, 'Forget “The notebook”?');
  await expect(forget).toContainText('The writer stops being told this. Scenes already written keep their text.');
  await forget.getByRole('button', { name: 'Forget' }).click();
  await expect.poll(async () => (await read(page, id)).continuity.map((f) => f.key)).toEqual(['Inn roof']);

  await page.getByRole('button', { name: 'Lore', exact: true }).click();
  await expect(page.getByTestId('lore-entries')).toContainText('The Flicker');
  await expect(page.getByTestId('lore-entries')).toContainText('island.md');
  await page.getByTestId('lore-menu-The Flicker').click();
  await page.getByRole('menuitem', { name: 'Remove…' }).click();
  await dialog(page, 'Remove “The Flicker”?').getByRole('button', { name: 'Remove' }).click();
  await expect(page.getByTestId('lore-empty-lore')).toContainText('No lore yet');
  await expect(page.getByTestId('lore-search')).toBeDisabled();
  await expect.poll(async () => (await read(page, id)).lore).toEqual([]);

  await page.getByRole('button', { name: 'Story so far' }).click();
  await expect(page.getByTestId('lore-sofar')).toContainText('Sequence 1 · The Light');
  await expect(page.getByTestId('lore-sofar')).toContainText('Wren keeps the lamp.');
  await expect(page.getByTestId('lore-sofar')).toContainText('1.1 Reading the Flicker: Wren reads the lamp.');
});

test('Run log says so when the story has made no model calls, and Clear waits for one', async ({ page }) => {
  const id = await seededStory(page, 'World Run Log Journey');
  await openRoute(page, `/stories/${id}/log`);
  await expect(page.getByTestId('runlog-count')).toHaveText('No model calls yet. Every call this story makes is listed here.');
  await expect(page.getByTestId('runlog-clear')).toBeDisabled();
  await expect(page.getByTestId('runlog-list')).toHaveCount(0);
  await page.getByTestId('runlog-filter').getByRole('button', { name: 'Failures' }).click();
  await expect(page.getByTestId('runlog-filter').getByRole('button', { name: 'Failures' })).toHaveClass(/\bon\b/);
});
