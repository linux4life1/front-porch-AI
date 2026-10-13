// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/** Same slot rule as Dart `normalizeRemoteApiUrl` (host case, trailing slash). */
export function normalizeRemoteApiUrl(url: string): string {
  const trimmed = url.trim();
  if (!trimmed) return '';
  try {
    const parsed = new URL(trimmed);
    if (!parsed.protocol || !parsed.hostname) {
      return trimmed.replace(/\/+$/, '');
    }
    const path = parsed.pathname.replace(/\/+$/, '');
    const port = parsed.port ? `:${parsed.port}` : '';
    return `${parsed.protocol}//${parsed.hostname.toLowerCase()}${port}${path}`;
  } catch {
    return trimmed.replace(/\/+$/, '');
  }
}

/** True when Settings already has a saved key for this remote URL. */
export function urlHasStoredApiKey(
  url: string,
  urlsWithKeys: string[] | undefined,
): boolean {
  const target = normalizeRemoteApiUrl(url);
  if (!target) return false;
  return (urlsWithKeys ?? []).some((u) => normalizeRemoteApiUrl(u) === target);
}

function loopbackPort(url: string): number | null {
  try {
    const parsed = new URL(url.trim());
    const host = parsed.hostname.toLowerCase();
    if (host !== 'localhost' && host !== '127.0.0.1') return null;
    const port = parsed.port
      ? Number(parsed.port)
      : parsed.protocol === 'https:'
        ? 443
        : 80;
    return port;
  } catch {
    return null;
  }
}

export function isLmStudioUrl(url: string): boolean {
  return loopbackPort(url) === 1234;
}

export function isOmlxUrl(url: string): boolean {
  return loopbackPort(url) === 8000;
}

const OMLX_API_V1 = 'http://localhost:8000/v1';

/** Same slot rule as Dart `remoteModelSlot`: KoboldCpp (or an unset worker)
 *  has none, oMLX always uses its fixed address, else the API URL. */
export function remoteModelSlot(backend: string, url: string): string {
  if (!backend || backend === 'kobold') return '';
  return normalizeRemoteApiUrl(backend === 'omlx' ? OMLX_API_V1 : url);
}

/** The model last used on that backend + URL, from the settings snapshot's
 *  slot → model map. Empty when the host has none. */
export function rememberedRemoteModel(
  backend: string,
  url: string,
  models: Record<string, string> | undefined,
): string {
  const slot = remoteModelSlot(backend, url);
  if (!slot || !models) return '';
  for (const [key, model] of Object.entries(models)) {
    if (normalizeRemoteApiUrl(key) === slot) return model;
  }
  return '';
}

/** [models] with [model] parked under backend + URL, so an unsaved pick
 *  survives switching away and back before Save. A blank never wipes. */
export function parkRemoteModel(
  backend: string,
  url: string,
  model: string,
  models: Record<string, string> | undefined,
): Record<string, string> {
  const slot = remoteModelSlot(backend, url);
  const next = { ...(models ?? {}) };
  if (!slot || !model.trim()) return next;
  for (const key of Object.keys(next)) {
    if (normalizeRemoteApiUrl(key) === slot) delete next[key];
  }
  next[slot] = model.trim();
  return next;
}
