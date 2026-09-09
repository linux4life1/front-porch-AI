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
