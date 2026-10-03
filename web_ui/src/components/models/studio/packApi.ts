// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's expression packs. The computer decides how the pictures are
// made (the Edit graph, or why it cannot); these only say what was chosen.

import { api } from "../../../api/client";

export interface PackSlot {
  emotion: string;
  state: "pending" | "generating" | "done" | "failed";
  keep: boolean;
  error: string | null;
  verdict?: { samePerson: boolean; expressionMatches: boolean; note: string };
}

/** GET /api/image/expression-pack: the pack on the computer, if any. */
export interface PackView {
  running: boolean;
  mode: "edit" | "img2img";
  origin: "phone" | "desktop";
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
  set: "starter" | "full";
  skipExisting: boolean;
  replaceExisting: boolean;
  denoise: number;
  prompt: string;
  referenceImage?: string;
  referenceFilename?: string;
  workspace?: boolean;
  baseSource?: 'currentPortrait';
}

const CHANGED = "fpai:pack-changed";

/** The panel and the banner both show the pack; what one does, the other hears. */
const announce = (view: PackView): PackView => {
  window.dispatchEvent(new Event(CHANGED));
  return view;
};

/** Calls [run] when the pack was started, stopped or imported from this phone. */
export const onPackChanged = (run: () => void) => {
  window.addEventListener(CHANGED, run);
  return () => window.removeEventListener(CHANGED, run);
};

export const fetchPack = () => api.get<PackView>("/api/image/expression-pack");
export const fetchPackPortrait = (characterId: string) =>
  api.get<{ characterId: string; image: string | null }>(`/api/image/expression-pack/source?characterId=${encodeURIComponent(characterId)}`);
export const discardPack = () => api.post('/api/image/expression-pack/discard', {}).then(() => {
  window.dispatchEvent(new Event(CHANGED));
});
export const startPack = (body: PackStart) =>
  api.post<PackView>("/api/image/expression-pack", body).then(announce);
export const cancelPack = () =>
  api.post<PackView>("/api/image/expression-pack/cancel", {}).then(announce);
export const importPack = (keep: string[]) =>
  api
    .post<PackView>("/api/image/expression-pack/import", { keep })
    .then(announce);
export const packPicture = (emotion: string) =>
  `/api/image/expression-pack/picture?emotion=${encodeURIComponent(emotion)}`;

export const resumePack = () =>
  api.post<PackView>("/api/image/expression-pack/resume", {}).then(announce);
export const rerollPack = (emotion: string) =>
  api
    .post<PackView>("/api/image/expression-pack/reroll", { emotion })
    .then(announce);
