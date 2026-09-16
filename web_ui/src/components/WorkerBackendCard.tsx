// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { isLmStudioUrl } from '../remoteApiKeys';
import {
  kWorkerDualLocalMessage,
  workerPairAllowed,
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
}

const OPTIONS: { id: string; label: string; backend: string; url?: string }[] = [
  { id: 'off', label: 'Off — same as chat', backend: '' },
  { id: 'kobold', label: 'KoboldCpp', backend: 'kobold' },
  { id: 'openrouter', label: 'OpenRouter', backend: 'openRouter', url: 'https://openrouter.ai/api/v1' },
  { id: 'nanogpt', label: 'Nano-GPT', backend: 'openRouter', url: 'https://nano-gpt.com/api/v1' },
  { id: 'lmstudio', label: 'LM Studio', backend: 'openRouter', url: 'http://localhost:1234/v1' },
  { id: 'omlx', label: 'oMLX', backend: 'omlx', url: 'http://localhost:8000/v1' },
  { id: 'custom', label: 'Custom', backend: 'openRouter', url: '' },
];

function selectedId(s: WorkerBackendFields): string {
  const type = s.workerBackend ?? '';
  if (!type) return 'off';
  if (type === 'kobold') return 'kobold';
  if (type === 'omlx') return 'omlx';
  const url = (s.workerRemoteApiUrl ?? '').trim();
  if (isLmStudioUrl(url)) return 'lmstudio';
  const match = OPTIONS.find((o) => o.backend === 'openRouter' && o.url && o.url === url);
  return match ? match.id : 'custom';
}

export function WorkerBackendCard({
  s,
  workerApiKey,
  onWorkerApiKey,
  onPatch,
}: {
  s: WorkerBackendFields;
  workerApiKey: string;
  onWorkerApiKey: (v: string) => void;
  onPatch: (p: Partial<WorkerBackendFields>) => void;
}) {
  const id = selectedId(s);
  const visible = OPTIONS.filter((o) => o.id !== 'omlx' || s.omlxAvailable === true);
  const showUrl = id === 'custom';
  const showModel = id !== 'off' && id !== 'kobold';
  const showKey = id === 'openrouter' || id === 'nanogpt' || id === 'custom';
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

  const onChange = (nextId: string) => {
    const opt = OPTIONS.find((o) => o.id === nextId);
    if (!opt) return;
    const patch: Partial<WorkerBackendFields> = { workerBackend: opt.backend };
    if (nextId === 'off') {
      patch.workerBackend = '';
    } else if (nextId === 'custom') {
      patch.workerRemoteApiUrl = '';
    } else if (opt.url) {
      patch.workerRemoteApiUrl = opt.url;
    }
    onPatch(patch);
  };

  return (
    <section className="card">
      <h3>Worker backend</h3>
      <p className="muted small">
        Side jobs (feelings, wiki/web lookup, journal, growth) can use a different
        host so chat speech stays on your main model. Off keeps everything on the
        backend above. Two cloud hosts — or one cloud and one local — are fine.
        Two local engines take turns on the GPU when unload/swap is available.
      </p>
      {banner && (
        <p className="error" data-testid="worker-dual-local-banner">{banner}</p>
      )}
      <label>
        Worker
        <select value={id} onChange={(e) => onChange(e.target.value)}>
          {visible.map((o) => (
            <option key={o.id} value={o.id}>{o.label}</option>
          ))}
        </select>
      </label>
      {showUrl && (
        <label>
          Worker API URL
          <input
            value={s.workerRemoteApiUrl ?? ''}
            onChange={(e) => onPatch({ workerRemoteApiUrl: e.target.value })}
            placeholder="https://your-server.example/v1"
          />
        </label>
      )}
      {showModel && (
        <label>
          Worker model
          <input
            value={s.workerRemoteModelName ?? ''}
            onChange={(e) => onPatch({ workerRemoteModelName: e.target.value })}
            placeholder="Different model id is fine on the same host"
          />
        </label>
      )}
      {showKey && (
        <label>
          Worker API key
          <input
            type="password"
            value={workerApiKey}
            onChange={(e) => onWorkerApiKey(e.target.value)}
            placeholder="leave blank to keep the saved key for this host"
          />
        </label>
      )}
      {id === 'kobold' && (
        <p className="muted small">
          Side jobs will start KoboldCPP using the model and GPU settings from
          the Models tab. Chat speech stays on your API host.
        </p>
      )}
    </section>
  );
}
