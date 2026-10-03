// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared Porch Stories client helpers: file downloads and text/binary export,
// reused by the studio's export bar and the reader so the logic lives in one
// place. (The shelf's status line comes from the relay: StoryListItem.shelf.)

import { api } from '../../api/client';

/** Trigger a browser download for a blob. */
export function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/** One sanitiser for every `<a download>` name (chat export + story files). */
export function safeDownloadStem(name: string, fallback: string): string {
  const cleaned = (name || fallback).replace(/[^\w.-]+/g, '_').replace(/^_+|_+$/g, '');
  return cleaned.length === 0 ? fallback : cleaned;
}

const safe = (name: string) => safeDownloadStem(name, 'story');

/** Download the assembled prose as plain text or markdown. */
export async function exportText(id: string, format: 'text' | 'markdown', title: string) {
  const r = await api.get<{ text: string }>(`/api/stories/${id}/export?format=${format}`);
  const blob = new Blob([r.text], { type: 'text/plain' });
  downloadBlob(blob, `${safe(title)}.${format === 'markdown' ? 'md' : 'txt'}`);
}

/** Download the EPUB (synthesized server-side). */
export async function exportEpub(id: string, title: string) {
  const blob = await api.getForBlob(`/api/stories/${id}/ebook`);
  downloadBlob(blob, `${safe(title)}.epub`);
}
