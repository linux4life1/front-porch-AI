// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A single backend picker (replacing the old Backend + Provider dropdowns,
// which overlapped). Each entry maps to a real BackendType; the OpenAI-compatible
// providers are first-class so the user chooses "where generation happens" once.
// `url` (when present) is the fixed API base for that provider — selecting it
// fills remoteApiUrl. `kind` drives which controls show:
//   local — host subprocess (KoboldCpp, optionally from a .kcpps preset): managed on the host.
//   api   — connect to an OpenAI-compatible server (model picker + maybe key).
// Shared by Settings and the in-chat model sheet so the two never disagree.

import { isLmStudioUrl } from './remoteApiKeys';

export interface BackendOption {
  id: string;
  label: string;
  backend: string; // BackendType the server understands
  url?: string;
  kind: 'local' | 'api';
}

/** The desktop's own sentence (kIntelMacLocalUnsupported) for a host that is
 *  an Intel Mac, which cannot run KoboldCpp. */
export const INTEL_MAC_LOCAL_UNSUPPORTED = 'Local inference is not supported on Intel Macs. Only Remote API mode is available.';

export const BACKEND_OPTIONS: BackendOption[] = [
  { id: 'kobold', label: 'KoboldCpp', backend: 'kobold', kind: 'local' },
  { id: 'openrouter', label: 'OpenRouter', backend: 'openRouter', url: 'https://openrouter.ai/api/v1', kind: 'api' },
  { id: 'nanogpt', label: 'Nano-GPT', backend: 'openRouter', url: 'https://nano-gpt.com/api/v1', kind: 'api' },
  { id: 'xai', label: 'xAI', backend: 'openRouter', url: 'https://api.x.ai/v1', kind: 'api' },
  { id: 'lmstudio', label: 'LM Studio', backend: 'openRouter', url: 'http://localhost:1234/v1', kind: 'api' },
  { id: 'omlx', label: 'oMLX', backend: 'omlx', url: 'http://localhost:8000/v1', kind: 'api' },
  { id: 'custom', label: 'Custom', backend: 'openRouter', url: '', kind: 'api' },
];

// Which unified backend option is active: local backends map 1:1; the
// OpenAI-compatible "openRouter" backend is disambiguated by its saved URL
// (Nano-GPT / OpenRouter / else Custom).
export function backendOptionId(backend: string, remoteApiUrl: string): string {
  if (backend === 'kobold') return 'kobold';
  if (backend === 'omlx') return 'omlx';
  if (isLmStudioUrl(remoteApiUrl)) return 'lmstudio';
  const match = BACKEND_OPTIONS.find(
    (o) => o.backend === 'openRouter' && o.url && o.url === remoteApiUrl.trim(),
  );
  return match ? match.id : 'custom';
}
