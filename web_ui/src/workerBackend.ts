// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { isLmStudioUrl, isOmlxUrl } from './remoteApiKeys';

export const kWorkerDualLocalMessage =
  "Chat speech and Realism evals can't both use a local engine at the same " +
  'time — they would fight over the GPU. Use a cloud/API host for one of ' +
  'them, or turn the worker off.';

function bareHostname(hostname: string): string {
  const host = hostname.toLowerCase();
  if (host.startsWith('[') && host.endsWith(']')) {
    return host.slice(1, -1);
  }
  return host;
}

function isByte(part: string): boolean {
  return /^\d{1,3}$/.test(part) && Number(part) <= 255;
}

/// This machine only: localhost, 127.0.0.0/8, ::1, 0.0.0.0.
/// WHATWG hostname keeps the brackets on [::1].
function isThisMachineUrl(url: string): boolean {
  try {
    const host = bareHostname(new URL(url.trim()).hostname);
    if (!host) return false;
    if (host === 'localhost' || host === '0.0.0.0' || host === '::1') {
      return true;
    }
    const parts = host.split('.');
    return parts.length === 4 && parts[0] === '127' && parts.every(isByte);
  } catch {
    return isLmStudioUrl(url) || isOmlxUrl(url);
  }
}

export function backendLaneIsLocal(backend: string, url: string): boolean {
  switch (backend.trim()) {
    case 'kobold':
    case 'omlx':
      return true;
    case 'openRouter':
      return isThisMachineUrl(url);
    default:
      return false;
  }
}

export function workerBackendIsOff(workerBackend: string): boolean {
  return workerBackend.trim() === '';
}

function resolvedLaneUrl(backend: string, url: string): string {
  if (backend === 'omlx') return 'http://localhost:8000/v1';
  if (backend === 'kobold') return '';
  return url.trim();
}

/** Same provider/URL family as chat speech. Empty worker inherits the mouth. */
export function workerHostMatchesChat(
  mouthType: string,
  mouthUrl: string,
  workerType: string,
  workerUrl: string,
): boolean {
  if (workerBackendIsOff(workerType)) return true;
  if (mouthType.trim() !== workerType.trim()) return false;
  if (mouthType === 'kobold') return true;
  return resolvedLaneUrl(mouthType, mouthUrl) ===
    resolvedLaneUrl(workerType, workerUrl);
}

/** Second key only when the host differs and that host has no saved key. */
export function workerShowsApiKeyField(opts: {
  sameHost: boolean;
  needsKey: boolean;
  vaultHasKey: boolean;
}): boolean {
  if (opts.sameHost) return false;
  if (!opts.needsKey) return false;
  return !opts.vaultHasKey;
}

export function workerPairAllowed(
  mouthType: string,
  mouthUrl: string,
  workerType: string,
  workerUrl: string,
  gpuSwapAvailable = false,
): boolean {
  if (workerBackendIsOff(workerType)) return true;
  const dual =
    backendLaneIsLocal(mouthType, mouthUrl) &&
    backendLaneIsLocal(workerType, workerUrl);
  if (!dual) return true;
  return gpuSwapAvailable;
}
