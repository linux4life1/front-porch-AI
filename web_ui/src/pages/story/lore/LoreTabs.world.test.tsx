// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Lore tab's chips for a story set in a world (docs/design/stories-in-worlds.md
// §5): copied entries say which world, room entries also say which room, and
// the story's own entries carry neither. Web twin of the chips test in
// test/ui/story_studio/lore_world_card_test.dart.

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it } from 'vitest';
import type { StoryProject } from '../../../storyTypes';
import { LoreTab } from './LoreTabs';
import { SceneRow } from '../structure/SceneRow';

const p = {
  world_id: 'conservatory',
  world_name: 'Greenhollow Estate',
  lore: [
    { topic: 'The bell', detail: 'Ten.', related_to: ['world:g', 'place:g'], valid_from_act: 1, valid_from_scene: 1 },
    { topic: 'The night vine', detail: 'Pepper.', related_to: ['world:g', 'place:conservatory'], valid_from_act: 1, valid_from_scene: 1 },
    { topic: 'The key', detail: 'Two keys.', related_to: [], valid_from_act: 1, valid_from_scene: 1 },
    { topic: 'Ledger (1)', detail: 'Wages.', related_to: ['file:ledger.txt'], valid_from_act: 1, valid_from_scene: 1 },
  ],
} as unknown as StoryProject;

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('copied entries say which world and which room; story lore and files keep their own chips', () => {
  act(() => root.render(createElement(LoreTab, { p, onRemove: () => {}, placeNames: { conservatory: 'The Conservatory' } })));
  const chips = Array.from(container.querySelectorAll('.s-chip')).map((c) => c.textContent);
  expect(chips.filter((c) => c === 'from Greenhollow Estate')).toHaveLength(2);
  expect(chips).toContain('The Conservatory');
  expect(chips).toContain('ledger.txt');
  // The house's own entry names no room, and the story's entry has no world chip.
  const rows = Array.from(container.querySelectorAll('.s-fact'));
  expect(rows[0].textContent).not.toContain('The Conservatory');
  expect(rows[2].querySelectorAll('.s-chip')).toHaveLength(0);
});

it('a new-place scene keeps its chip outside the clipped detail line, so a phone still shows it', () => {
  const story = {
    world_id: 'conservatory',
    world_name: 'Greenhollow Estate',
    engine_mode: 'studio',
    lenses_enabled: false,
    scenes: { '1': [{ number: 1, title: 'The gate at dusk', cast_names: ['Hilde'], location: 'the Gatehouse — dusk', place_id: '' }] },
    beats: {},
  } as unknown as StoryProject;
  const noop = () => {};
  act(() => root.render(createElement(SceneRow, {
    p: story, act: 1, index: 0, running: false, isNext: false, lenses: [],
    actions: { open: noop, write: noop, planBeats: noop, edit: noop, insertAfter: noop, rewrite: noop, remove: noop },
  })));
  const chip = Array.from(container.querySelectorAll('.s-chip')).find((c) => c.textContent === 'new place');
  expect(chip).toBeTruthy();
  // `.d` is the one-line ellipsised detail; a chip inside it is cut off on a narrow row.
  expect(chip!.closest('.d')).toBeNull();
  expect(container.querySelector('.d')?.textContent).toBe('Hilde · the Gatehouse — dusk');
});
