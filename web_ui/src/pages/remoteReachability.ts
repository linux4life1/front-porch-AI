// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The remote API status words, as the desktop's remoteBackendStatusLabel
// says them. Green "Ready" is only a model chosen on a server that answered.

export type RemoteReachability = 'unknown' | 'checking' | 'reachable' | 'unreachable';

export type RemoteStatusTone = 'ok' | 'busy' | 'down' | 'configured';

export function remoteReachabilityLabel(
  configured: boolean,
  reachability?: string,
): { text: string; tone: RemoteStatusTone } {
  if (!configured) {
    // The server answered before a model was chosen: connected, not red.
    return reachability === 'reachable'
      ? { text: 'Connected — pick a model', tone: 'configured' }
      : { text: 'Not configured', tone: 'down' };
  }
  switch (reachability) {
    case 'checking':
      return { text: 'Checking…', tone: 'busy' };
    case 'reachable':
      return { text: 'Ready', tone: 'ok' };
    case 'unreachable':
      return { text: 'Configured but unreachable', tone: 'down' };
    default:
      return { text: 'Configured', tone: 'configured' };
  }
}
