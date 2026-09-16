// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';
import { isLmStudioUrl, urlHasStoredApiKey } from '../remoteApiKeys';
import { ModelPicker } from './ModelPicker';
import {
  kWorkerDualLocalMessage,
  workerBackendIsOff,
  workerHostMatchesChat,
  workerPairAllowed,
  workerShowsApiKeyField,
} from '../workerBackend';

export interface WorkerBackendFields {
  workerBackend?: string;
  workerRemoteApiUrl?: string;
  workerRemoteModelName?: string;
  workerEnabled?: boolean;
  workerRefusedDualLocal?: boolean;
  workerDualLocalMessage?: string;
  workerUnreadyMessage?: string;
  workerGpuSwapAvailable?: boolean;
  omlxAvailable?: boolean;
  backend?: string;
  remoteApiUrl?: string;
  remoteApiUrlsWithKeys?: string[];
}

const HOSTS: { id: string; label: string; backend: string; url?: string }[] = [
  { id: 'kobold', label: 'KoboldCpp', backend: 'kobold' },
  { id: 'openrouter', label: 'OpenRouter', backend: 'openRouter', url: 'https://openrouter.ai/api/v1' },
  { id: 'nanogpt', label: 'Nano-GPT', backend: 'openRouter', url: 'https://nano-gpt.com/api/v1' },
  { id: 'lmstudio', label: 'LM Studio', backend: 'openRouter', url: 'http://localhost:1234/v1' },
  { id: 'omlx', label: 'oMLX', backend: 'omlx', url: 'http://localhost:8000/v1' },
  { id: 'custom', label: 'Custom', backend: 'openRouter', url: '' },
];

function selectedId(s: WorkerBackendFields): string {
  const type = s.workerBackend ?? '';
  if (!type) return '';
  if (type === 'kobold') return 'kobold';
  if (type === 'omlx') return 'omlx';
  const url = (s.workerRemoteApiUrl ?? '').trim();
  if (isLmStudioUrl(url)) return 'lmstudio';
  const match = HOSTS.find((o) => o.backend === 'openRouter' && o.url && o.url === url);
  return match ? match.id : 'custom';
}

export function WorkerBackendCard({
  s,
  workerApiKey,
  onWorkerApiKey,
  onPatch,
  savedRemoteApiUrl = '',
  chatApiKey = '',
  currentPassword = '',
  totpCode = '',
  totpEnabled = false,
  onTotpRequired,
}: {
  s: WorkerBackendFields;
  workerApiKey: string;
  onWorkerApiKey: (v: string) => void;
  onPatch: (p: Partial<WorkerBackendFields>) => void;
  savedRemoteApiUrl?: string;
  chatApiKey?: string;
  currentPassword?: string;
  totpCode?: string;
  totpEnabled?: boolean;
  onTotpRequired?: () => void;
}) {
  const off = workerBackendIsOff(s.workerBackend ?? '');
  const [pickingDifferent, setPickingDifferent] = useState(!off);
  const different = !off || pickingDifferent;
  const id = selectedId(s);
  const visible = HOSTS.filter((o) => o.id !== 'omlx' || s.omlxAvailable === true);
  const sameHost = workerHostMatchesChat(
    s.backend ?? '',
    s.remoteApiUrl ?? '',
    s.workerBackend ?? '',
    s.workerRemoteApiUrl ?? '',
  );
  const workerUrl = (s.workerRemoteApiUrl ?? '').trim();
  const vaultHasKey = urlHasStoredApiKey(workerUrl, s.remoteApiUrlsWithKeys);
  const needsKeyFamily = id === 'openrouter' || id === 'nanogpt' || id === 'custom';
  const showUrl = different && !off && !sameHost && id === 'custom';
  const showKey = different &&
    !off &&
    workerShowsApiKeyField({
      sameHost,
      needsKey: needsKeyFamily,
      vaultHasKey,
    });
  const showSavedKeyHint =
    different && !off && !sameHost && needsKeyFamily && vaultHasKey;
  const showModel =
    different && !off && id !== 'kobold' && id !== '';
  const pairOk = workerPairAllowed(
    s.backend ?? '',
    s.remoteApiUrl ?? '',
    s.workerBackend ?? '',
    s.workerRemoteApiUrl ?? '',
    s.workerGpuSwapAvailable === true,
  );
  const refused = !pairOk || s.workerRefusedDualLocal === true;
  const banner = refused
    ? (s.workerDualLocalMessage || kWorkerDualLocalMessage)
    : (s.workerUnreadyMessage ?? '');

  const onHostChange = (nextId: string) => {
    const opt = HOSTS.find((o) => o.id === nextId);
    if (!opt) return;
    const patch: Partial<WorkerBackendFields> = { workerBackend: opt.backend };
    if (nextId === 'custom') {
      patch.workerRemoteApiUrl = '';
    } else if (opt.url) {
      patch.workerRemoteApiUrl = opt.url;
    }
    onPatch(patch);
  };

  const pickerUrl = sameHost ? (s.remoteApiUrl ?? '') : workerUrl;
  const pickerKey = sameHost ? chatApiKey : workerApiKey;

  return (
    <div className="side-jobs" data-testid="side-jobs-card">
      <h4>Realism evals</h4>
      <p className="muted small">
        Feelings, wiki/web, journal, growth can use another host. Chat speech stays above.
        Two local engines take turns on the GPU when unload/swap is available.
      </p>
      {different && banner && (
        <p className="error" data-testid="worker-dual-local-banner">{banner}</p>
      )}
      <div className="side-jobs-seg" role="group" aria-label="Realism evals host">
        <button
          type="button"
          data-testid="side-jobs-same-as-chat"
          className={!different ? 'seg-on' : 'seg-off'}
          aria-pressed={!different}
          onClick={() => {
            setPickingDifferent(false);
            onPatch({ workerBackend: '' });
          }}
        >
          Same as chat
        </button>
        <button
          type="button"
          data-testid="side-jobs-different-host"
          className={different ? 'seg-on' : 'seg-off'}
          aria-pressed={different}
          onClick={() => setPickingDifferent(true)}
        >
          Different host…
        </button>
      </div>
      {!different && (
        <p className="muted small" data-testid="side-jobs-same-host-status">
          Realism evals use the chat host above.
        </p>
      )}
      {different && (
        <>
          <label>
            Host
            <select
              data-testid="side-jobs-host"
              value={id}
              onChange={(e) => onHostChange(e.target.value)}
            >
              {off && <option value="">Choose a host…</option>}
              {visible.map((o) => (
                <option key={o.id} value={o.id}>{o.label}</option>
              ))}
            </select>
          </label>
          {!off && sameHost && (
            <p className="muted small" data-testid="side-jobs-same-host-status">
              Realism evals use the chat host above. Pick a model only.
            </p>
          )}
          {showUrl && (
            <label>
              API URL
              <input
                data-testid="side-jobs-worker-url"
                value={s.workerRemoteApiUrl ?? ''}
                onChange={(e) => onPatch({ workerRemoteApiUrl: e.target.value })}
                placeholder="https://your-server.example/v1"
              />
            </label>
          )}
          {showModel && (
            <label>
              Model
              <ModelPicker
                apiUrl={pickerUrl}
                apiKey={pickerKey}
                savedApiUrl={savedRemoteApiUrl}
                currentPassword={currentPassword}
                totpCode={totpCode}
                totpEnabled={totpEnabled}
                onTotpRequired={onTotpRequired}
                value={s.workerRemoteModelName ?? ''}
                onChange={(modelId) => onPatch({ workerRemoteModelName: modelId })}
              />
            </label>
          )}
          {showKey && (
            <label>
              API key
              <input
                data-testid="side-jobs-worker-key"
                type="password"
                value={workerApiKey}
                onChange={(e) => onWorkerApiKey(e.target.value)}
                placeholder="Key for this host"
              />
            </label>
          )}
          {showSavedKeyHint && (
            <p className="muted small" data-testid="side-jobs-saved-key-hint">
              Using the saved key for this host.
            </p>
          )}
          {id === 'kobold' && (
            <p className="muted small">
              Realism evals will start KoboldCPP using the model and GPU settings from
              the Models tab. Chat speech stays on your API host.
            </p>
          )}
        </>
      )}
    </div>
  );
}
