// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What New Story reads from the library: the characters (with their portrait
// URL) and the persona's name.

import { api } from '../../../api/client';
import type { CharacterRow } from './draft';

/** The portrait thumbnail for a library character, or undefined when it has none (the avatar shows initials). */
export function characterAvatar(c: CharacterRow): string | undefined {
  return c.hasAvatar === false ? undefined : api.avatarUrl(`/api/characters/${c.id}/avatar`, 96, c.avatarVersion);
}

export async function loadCharacters(): Promise<CharacterRow[]> {
  return api.get<CharacterRow[]>('/api/characters');
}

/** The active persona's name, "User" when none is set up. */
export async function loadPersonaName(): Promise<string> {
  try {
    const r = await api.get<{ personas: { name: string; active: boolean }[] }>('/api/personas');
    return r.personas.find((p) => p.active)?.name || 'User';
  } catch {
    return 'User';
  }
}
