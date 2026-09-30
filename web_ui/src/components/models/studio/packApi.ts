// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's expression packs. The computer decides how the pictures are
// made (the Edit graph, or why it cannot); these only say what was chosen.

import { api } from '../../../api/client';

export interface PackSlot {
  emotion: string;
  state: 'pending' | 'generating' | 'done' | 'failed';
  keep: boolean;
  error: string | null;
  verdict?: { samePerson: boolean; expressionMatches: boolean; note: string };
}

/** GET /api/image/expression-pack: the pack on the computer, if any. */
export interface PackView {
  running: boolean;
  mode: 'edit' | 'img2img';
  origin: 'phone' | 'desktop';
  characterId: string | null;
  characterName: string;
  total: number;
  done: number;
  kept: number;
  imported: number | null;
  canImport: boolean;
  /** E.g. that the base picture was converted to a PNG; absent on older computers. */
  note?: string | null;
  slots: PackSlot[];
}

export interface PackStart {
  characterId: string;
  set: 'starter' | 'full';
  skipExisting: boolean;
  replaceExisting: boolean;
  denoise: number;
  prompt: string;
  referenceImage?: string;
  referenceFilename?: string;
}

export const fetchPack = () => api.get<PackView>('/api/image/expression-pack');
export const startPack = (body: PackStart) => api.post<PackView>('/api/image/expression-pack', body);
export const cancelPack = () => api.post<PackView>('/api/image/expression-pack/cancel', {});
export const importPack = (keep: string[]) =>
  api.post<PackView>('/api/image/expression-pack/import', { keep });
export const packPicture = (emotion: string) =>
  `/api/image/expression-pack/picture?emotion=${encodeURIComponent(emotion)}`;
