// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where a group's new chats meet — the web twin of the desktop
// GroupWorldChoice (lib/services/world_store/group_world_choice.dart) and
// the summary sentence in lib/ui/widgets/group_setting_picker.dart.

import { indexById, topOf, type TreeWorld } from '../../pages/worlds/locations';

/** One Setting (a top-level world, which starts at its starred place, or a
 *  place inside one, which starts there) and any lore-only worlds. */
export interface WorldChoice {
  settingId: string | null;
  loreIds: string[];
}

export const NO_WORLD: WorldChoice = { settingId: null, loreIds: [] };

const idOf = (w: TreeWorld): string => w.id ?? w.name;

/** Pick a world: it becomes the Setting and stops being lore-only. */
export function pickWorld(choice: WorldChoice, worldId: string | null): WorldChoice {
  return {
    settingId: worldId,
    loreIds: choice.loreIds.filter((id) => id !== worldId),
  };
}

/** Pick a place inside [root]. The starred place is stored as the world
 *  itself, so the group follows the star if the author moves it later. */
export function pickPlace(root: TreeWorld, placeId: string): WorldChoice['settingId'] {
  return placeId === root.defaultPlaceId ? idOf(root) : placeId;
}

export function toggleLore(choice: WorldChoice, worldId: string): WorldChoice {
  const on = choice.loreIds.includes(worldId);
  return {
    settingId: choice.settingId,
    loreIds: on ? choice.loreIds.filter((id) => id !== worldId) : [...choice.loreIds, worldId],
  };
}

/** The world whose climate a slot runs: the nearest climate-enabled world up
 *  its chain, and none when the top world has climate off (as on desktop). */
export function climateAuthor(id: string, byId: Map<string, TreeWorld>): TreeWorld | null {
  const chain: TreeWorld[] = [];
  let w = byId.get(id);
  while (w && chain.length < 32) {
    chain.push(w);
    const p = w.parentWorldId;
    w = p ? byId.get(p) : undefined;
  }
  if (chain.length === 0 || chain[chain.length - 1].climateEnabled === false) return null;
  return chain.find((c) => c.climateEnabled !== false) ?? null;
}

/** Where a new chat starts for [choice]: the place, and the world it is in. */
export function startOf(
  choice: WorldChoice,
  byId: Map<string, TreeWorld>,
): { start: TreeWorld; root: TreeWorld } | null {
  const setting = choice.settingId ? byId.get(choice.settingId) : undefined;
  if (!setting) return null;
  const root = topOf(setting, byId);
  if (idOf(setting) !== idOf(root)) return { start: setting, root };
  const star = root.defaultPlaceId ? byId.get(root.defaultPlaceId) : undefined;
  return { start: star ?? root, root };
}

/** One plain sentence saying where new chats start and what they read. */
export function settingSummary(
  choice: WorldChoice,
  worlds: TreeWorld[],
  weatherOf: (id: string) => string | null,
): string {
  const byId = indexById(worlds);
  const at = startOf(choice, byId);
  let out: string;
  if (!at) {
    out = 'New chats start with no world.';
  } else {
    const { start, root } = at;
    out =
      idOf(start) === idOf(root)
        ? `New chats start in ${root.name}.`
        : `New chats start at ${start.name} in ${root.name}.`;
    const weather = weatherOf(idOf(start));
    out += weather ? ` Weather: ${weather}.` : ' No weather.';
  }
  const lore = choice.loreIds.map((id) => byId.get(id)?.name).filter((n): n is string => !!n);
  if (lore.length > 0) {
    const names =
      lore.length === 1 ? lore[0] : `${lore.slice(0, -1).join(', ')} and ${lore[lore.length - 1]}`;
    out += ` Also reads lore from ${names}, with no weather from ${lore.length === 1 ? 'it' : 'them'}.`;
  }
  return out;
}

/** The climate names a slot brings, for display: the relay's climateName,
 *  else the name from [climates] (/api/worlds/climates). */
export function weatherLabels(
  worlds: TreeWorld[],
  climates: { id: string; displayName: string }[],
): (id: string) => string | null {
  const byId = indexById(worlds);
  const names = new Map(climates.map((c) => [c.id, c.displayName]));
  return (id) => {
    const author = climateAuthor(id, byId);
    if (!author) return null;
    if (author.climateName) return author.climateName;
    const biome = author.biomeId ?? 'temperate';
    return names.get(biome) ?? 'Custom weather';
  };
}

/** Top-level world id → the members whose cards link it, for "Linked by". */
export function linkedByMembers(
  members: { name: string; worldNames?: string[] }[],
  worlds: TreeWorld[],
): Map<string, string[]> {
  const byId = indexById(worlds);
  const out = new Map<string, string[]>();
  for (const m of members) {
    for (const ref of m.worldNames ?? []) {
      const w = byId.get(ref) ?? worlds.find((x) => x.name === ref);
      if (!w) continue;
      const top = idOf(topOf(w, byId));
      const names = out.get(top) ?? [];
      if (!names.includes(m.name)) names.push(m.name);
      out.set(top, names);
    }
  }
  return out;
}
