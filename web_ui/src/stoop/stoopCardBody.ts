// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure readers for Stoop card JSON so the detail page can show group members
// and world climate/lore the same way desktop does.

import type { StoopCard } from './stoopTypes';

export type CardMap = Record<string, unknown>;

function asMap(v: unknown): CardMap | undefined {
  return v && typeof v === 'object' && !Array.isArray(v)
    ? (v as CardMap)
    : undefined;
}

function str(card: CardMap, key: string): string {
  const v = card[key];
  return typeof v === 'string' ? v.trim() : '';
}

function climateFlag(card: CardMap): boolean | undefined {
  for (const key of ['climate_enabled', 'climateEnabled']) {
    const raw = card[key];
    if (typeof raw === 'boolean') return raw;
    if (typeof raw === 'number') return raw !== 0;
  }
  return undefined;
}

/** Full .fpworld envelopes without the additive flag are legacy climate-on. */
export function stoopWorldClimateEnabled(card: CardMap): boolean {
  return climateFlag(card) ?? true;
}

/** List rows with no envelope use the additive DTO flag and default off. */
export function stoopCardClimateEnabled(card: StoopCard): boolean {
  const envelope = asMap(card.card) ?? {};
  const envelopeFlag = climateFlag(envelope);
  if (envelopeFlag !== undefined) return envelopeFlag;
  return (
    climateFlag(card as unknown as CardMap) ??
    ('formatVersion' in envelope ||
      'name' in envelope ||
      'biome' in envelope ||
      'lorebook' in envelope ||
      'lorebooks' in envelope)
  );
}

export function stoopMembers(card: CardMap): CardMap[] {
  const raw = card.raw_member_data;
  const alt = card.members;
  const list = Array.isArray(raw) ? raw : Array.isArray(alt) ? alt : [];
  return list.map((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return {};
    const rec = entry as CardMap;
    const data = asMap(rec.data);
    return data ?? rec;
  });
}

export function stoopGreetings(card: CardMap): string[] {
  const first = str(card, 'first_mes') || str(card, 'first_message');
  const raw = card.alternate_greetings;
  const alts = Array.isArray(raw)
    ? raw.filter((a): a is string => typeof a === 'string' && a.trim() !== '').map((a) => a.trim())
    : [];
  return [...(first ? [first] : []), ...alts];
}

export function stoopWorldClimate(card: CardMap): string {
  if (!stoopWorldClimateEnabled(card)) return '';
  const biome = asMap(card.biome);
  if (!biome) return '';
  const name = typeof biome.displayName === 'string' ? biome.displayName.trim() : '';
  const feel =
    typeof biome.feel === 'string'
      ? biome.feel.trim()
      : typeof biome.description === 'string'
        ? biome.description.trim()
        : '';
  return [name, feel].filter(Boolean).join(' — ');
}

export function stoopWorldTraits(card: CardMap): string[] {
  if (!stoopWorldClimateEnabled(card)) return [];
  const traits = asMap(card.place_traits);
  if (!traits) return [];
  return Object.entries(traits).map(
    ([k, v]) => `${k.split('_').join(' ')}: ${String(v)}`,
  );
}

export function stoopLoreEntries(card: CardMap): { name: string; content: string }[] {
  const lore = asMap(card.lorebook) ?? asMap(card.character_book);
  const raw = lore?.entries;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((e) => {
    const m = asMap(e);
    if (!m) return [];
    const content = typeof m.content === 'string' ? m.content.trim() : '';
    if (!content) return [];
    const name =
      (typeof m.comment === 'string' && m.comment.trim()) ||
      (typeof m.name === 'string' && m.name.trim()) ||
      'Entry';
    return [{ name, content }];
  });
}

export function stoopCardLooksLikeWorld(card: CardMap): boolean {
  if (hasMembers(card)) return false;
  if ('first_mes' in card || 'personality' in card) return false;
  return 'biome' in card || 'place_traits' in card || asMap(card.lorebook) != null;
}

function hasMembers(card: CardMap): boolean {
  return Array.isArray(card.members) || Array.isArray(card.raw_member_data);
}

/** Mirror of Dart `stoopImportKind` so display and download agree. */
export function stoopCardKind(
  type: string | undefined,
  card: CardMap,
): 'SOLO' | 'GROUP' | 'WORLD' {
  const hinted =
    type === 'GROUP' || type === 'WORLD' || type === 'SOLO' ? type : undefined;
  if (stoopCardLooksLikeWorld(card) && (!hinted || hinted === 'SOLO')) return 'WORLD';
  if (hasMembers(card) && (!hinted || hinted === 'SOLO')) return 'GROUP';
  return hinted ?? 'SOLO';
}

export function stoopGroupTurnLabel(card: CardMap, memberCount: number): string {
  const to = String(card.turn_order ?? card.turnOrder ?? 'roundRobin');
  const mode = to === 'random' ? 'Random' : 'Round Robin';
  const n = memberCount === 1 ? '1 character' : `${memberCount} characters`;
  return `${mode} · ${n}`;
}
