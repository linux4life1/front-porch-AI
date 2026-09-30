// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's side of the CivitAI relay: search, the saved key, and a
// download the computer runs while the phone watches.

import { api, ApiError } from '../../../api/client';
import type { CivitaiJob } from './types';

export interface CivitaiRow {
  filename: string;
  versionId: number;
  type: string;
  adult: boolean;
  name?: string;
  downloads?: number;
  preview?: string;
  description?: string;
}

interface SearchBody {
  items?: {
    filename?: string;
    versionId?: number;
    type?: string;
    adult?: boolean;
    name?: string;
    downloads?: number;
    previewUrl?: string | null;
    description?: string;
  }[];
  needsCredential?: boolean;
}

export async function searchCivitai(opts: {
  query: string;
  lora: boolean;
  adult: boolean;
  base: string;
}): Promise<{ rows: CivitaiRow[]; needsCredential: boolean }> {
  const q = new URLSearchParams({
    q: opts.query,
    adult: opts.adult ? 'true' : 'false',
    sheet: opts.lora ? 'lora' : 'model',
    base: opts.base,
  });
  const body = await api.get<SearchBody>(`/api/image/civitai/search?${q.toString()}`);
  const rows = (body.items ?? []).flatMap((row) => {
    if (!row.filename || typeof row.versionId !== 'number') return [];
    return [
      {
        filename: row.filename,
        versionId: row.versionId,
        type: row.type ?? '',
        adult: row.adult === true,
        name: row.name,
        downloads: row.downloads ?? 0,
        preview: row.previewUrl ?? undefined,
        description: row.description,
      },
    ];
  });
  return { rows, needsCredential: body.needsCredential === true };
}

export const keySaved = () =>
  api.get<{ saved?: boolean }>('/api/image/civitai/credential').then((b) => b.saved === true);

/** Saving a key is credential-grade: it needs the web password. */
export function saveKey(token: string, password: string, totpCode?: string) {
  const body: Record<string, unknown> = { token, currentPassword: password };
  if (totpCode?.trim()) body.totpCode = totpCode.trim();
  return api.post<{ saved?: boolean }>('/api/image/civitai/credential', body);
}

export const installedNames = (backend: string) =>
  api.get<{ bases?: string[]; models?: string[]; loras?: string[] }>(
    `/api/image/civitai/installed?backend=${encodeURIComponent(backend)}`,
  );

export const startDownload = (body: {
  versionId: number;
  backend: string;
  adult: boolean;
  filename: string;
  lora: boolean;
}) => api.post<CivitaiJob>('/api/image/civitai/download', body);

export const jobStatus = (id: string) =>
  api.get<CivitaiJob>(`/api/image/civitai/download/status?job=${encodeURIComponent(id)}`);

export const cancelJob = (id: string) =>
  api.post('/api/image/civitai/download/cancel', { job: id });

/** The words for a failed search or download: the server's own when it sent
 *  any, and a plain fallback for a raw error page or no answer. */
export function civitaiNote(error: unknown, fallback: string): string {
  const message = error instanceof ApiError ? error.message.trim() : '';
  if (message.length === 0 || message.startsWith('<')) return fallback;
  return message;
}
