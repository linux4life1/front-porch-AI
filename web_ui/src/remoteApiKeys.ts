// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/** True when Settings already has a saved key for this remote URL. */
export function urlHasStoredApiKey(
  url: string,
  urlsWithKeys: string[] | undefined,
): boolean {
  const target = url.trim();
  if (!target) return false;
  return (urlsWithKeys ?? []).some((u) => u.trim() === target);
}
