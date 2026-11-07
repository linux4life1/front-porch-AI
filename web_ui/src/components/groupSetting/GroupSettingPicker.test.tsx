// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web group Setting picker: one world, the starred place stored as the
// world itself, another place as itself, lore-only worlds apart, and the
// same summary sentence the desktop shows.

import { act, createElement, useState } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it } from 'vitest';
import type { TreeWorld } from '../../pages/worlds/locations';
import { GroupSettingPicker } from './GroupSettingPicker';
import { NO_WORLD, settingSummary, weatherLabels, type WorldChoice } from './groupWorldChoice';

const WORLDS: TreeWorld[] = [
  { id: 'vale', name: 'Green Vale', climateEnabled: true, biomeId: 'temperate', defaultPlaceId: 'mill' },
  { id: 'mill', name: 'The Mill', parentWorldId: 'vale', climateEnabled: false },
  { id: 'bridge', name: 'Old Bridge', parentWorldId: 'vale', climateEnabled: false },
  { id: 'reach', name: 'Salt Reach', climateEnabled: true, biomeId: 'coastal' },
  { id: 'attic', name: 'Attic Books', climateEnabled: false },
];
const CLIMATES = [
  { id: 'temperate', displayName: 'Temperate' },
  { id: 'coastal', displayName: 'Coastal' },
];

let container: HTMLDivElement;
let root: Root;
let last: WorldChoice;

function Harness({ start }: { start: WorldChoice }) {
  const [v, setV] = useState(start);
  return createElement(GroupSettingPicker, {
    value: v,
    onChange: (next: WorldChoice) => {
      last = next;
      setV(next);
    },
    worlds: WORLDS,
    weatherOf: weatherLabels(WORLDS, CLIMATES),
  });
}

function mount(start: WorldChoice) {
  act(() => root.render(createElement(Harness, { start })));
}

const tap = (id: string) =>
  act(() => (container.querySelector(`[data-testid="${id}"]`) as HTMLButtonElement).click());

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  last = NO_WORLD;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('picks one world at a time and drops it from lore', () => {
  mount({ settingId: 'vale', loreIds: ['reach'] });
  tap('group-setting-world-reach');
  expect(last).toEqual({ settingId: 'reach', loreIds: [] });
});

it('stores the star as the world and another place as itself', () => {
  mount({ settingId: 'vale', loreIds: [] });
  tap('group-setting-place-bridge');
  expect(last.settingId).toBe('bridge');
  tap('group-setting-place-mill');
  expect(last.settingId).toBe('vale');
});

it('lists lore-only worlds apart and never the Setting', () => {
  mount({ settingId: 'vale', loreIds: [] });
  tap('group-setting-lore-toggle');
  expect(container.querySelector('[data-testid="group-setting-lore-vale"]')).toBeNull();
  tap('group-setting-lore-attic');
  expect(last).toEqual({ settingId: 'vale', loreIds: ['attic'] });
});

it('says where new chats start, in the desktop words', () => {
  const weather = weatherLabels(WORLDS, CLIMATES);
  expect(settingSummary({ settingId: 'vale', loreIds: ['attic'] }, WORLDS, weather)).toBe(
    'New chats start at The Mill in Green Vale. Weather: Temperate. ' +
      'Also reads lore from Attic Books, with no weather from it.',
  );
  expect(settingSummary({ settingId: 'bridge', loreIds: [] }, WORLDS, weather)).toBe(
    'New chats start at Old Bridge in Green Vale. Weather: Temperate.',
  );
  expect(settingSummary({ settingId: 'attic', loreIds: [] }, WORLDS, weather)).toBe(
    'New chats start in Attic Books. No weather.',
  );
  expect(settingSummary(NO_WORLD, WORLDS, weather)).toBe('New chats start with no world.');
});
