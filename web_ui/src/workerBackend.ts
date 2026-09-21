// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { isLmStudioUrl, isOmlxUrl } from './remoteApiKeys';

export const kWorkerDualLocalMessage =
  "Chat speech and Realism evals can't both use a local engine at the same " +
  'time — they would fight over the GPU. Use a cloud/API host for one of ' +
  'them, or turn the worker off.';

function isLoopbackOrLan(url: string): boolean {
  try {
    const host = new URL(url.trim()).hostname.toLowerCase();
    if (!host) return false;
    if (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host === '0.0.0.0' ||
      host === '::1'
    ) {
      return true;
    }
    if (host.endsWith('.local')) return true;
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(host)) return true;
    if (/^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(host)) return true;
    return false;
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
      return isLoopbackOrLan(url);
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
