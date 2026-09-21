// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure helpers for Image Studio remote chips + searchable picker (web).

export const kNanoGptApiV1 = 'https://nano-gpt.com/api/v1';
export const kOpenRouterApiV1 = 'https://openrouter.ai/api/v1';

export interface ImageRemoteHost {
  id: string;
  label: string;
  url: string;
  hasKey: boolean;
}

export interface ImageRemoteModel {
  id: string;
  name: string;
  label: string;
  isPaid: boolean;
  pricingInfo?: string | null;
}

export function imageModelListLabel(m: {
  name?: string;
  id: string;
  isPaid?: boolean;
  pricingInfo?: string | null;
}): string {
  const display = (m.name && m.name.trim()) || m.id;
  if (m.pricingInfo) return `${display} — ${m.pricingInfo}`;
  return m.isPaid === false ? `${display} · Pro` : `${display} · paid`;
}

/** Local Comfy/A1111 weight filenames — never send these as Nano/OR model ids. */
export function looksLikeLocalImageModel(id: string): boolean {
  const s = id.trim().toLowerCase();
  if (!s) return false;
  if (s.includes('\\') || s.startsWith('file:') || s.startsWith('~/') || s.startsWith('/')) {
    return true;
  }
  if (/^[a-z]:[\\/]/.test(s)) return true;
  return /\.(ckpt|safetensors|sft|pt|pth)(?:\b|$)/.test(s);
}

export function filterImageModels<T extends { id: string; name?: string; label?: string }>(
  models: T[],
  query: string,
): T[] {
  const q = query.trim().toLowerCase();
  if (!q) return models;
  return models.filter((m) => {
    const hay = `${m.name ?? ''} ${m.id} ${m.label ?? ''}`.toLowerCase();
    return hay.includes(q);
  });
}

export function sortImageModelsForPicker<T extends { isPaid?: boolean; name?: string; id: string }>(
  models: T[],
): T[] {
  return [...models].sort((a, b) => {
    const ap = a.isPaid !== false;
    const bp = b.isPaid !== false;
    if (ap !== bp) return ap ? 1 : -1;
    const an = (a.name || a.id).toLowerCase();
    const bn = (b.name || b.id).toLowerCase();
    return an.localeCompare(bn);
  });
}
