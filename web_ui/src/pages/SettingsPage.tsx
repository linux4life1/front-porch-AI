// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { PersonaManager } from '../components/PersonaManager';
import { ModelPicker } from '../components/ModelPicker';

// A single backend picker (replacing the old Backend + Provider dropdowns,
// which overlapped). Each entry maps to a real BackendType; the OpenAI-compatible
// providers are first-class so the user chooses "where generation happens" once.
// `url` (when present) is the fixed API base for that provider — selecting it
// fills remoteApiUrl. `kind` drives which controls show:
//   local — host subprocess (KoboldCpp / Pseudo-Remote): managed on the host.
//   api   — connect to an OpenAI-compatible server (model picker + maybe key).
interface BackendOption {
  id: string;
  label: string;
  backend: string; // BackendType the server understands
  url?: string;
  kind: 'local' | 'api';
}
const BACKEND_OPTIONS: BackendOption[] = [
  { id: 'kobold', label: 'KoboldCpp (local)', backend: 'kobold', kind: 'local' },
  { id: 'pseudoRemote', label: 'Pseudo-Remote (local server)', backend: 'pseudoRemote', kind: 'local' },
  { id: 'omlx', label: 'oMLX (local API)', backend: 'omlx', url: 'http://localhost:8000/v1', kind: 'api' },
  { id: 'nanogpt', label: 'Nano-GPT', backend: 'openRouter', url: 'https://nano-gpt.com/api/v1', kind: 'api' },
  { id: 'openrouter', label: 'OpenRouter', backend: 'openRouter', url: 'https://openrouter.ai/api/v1', kind: 'api' },
  { id: 'custom', label: 'Custom API (OpenAI-compatible)', backend: 'openRouter', url: '', kind: 'api' },
];

interface Gen {
  temperature: number;
  minP: number;
  repeatPenalty: number;
  maxLength: number;
  minLength: number;
  dynamicTempEnabled: boolean;
}
interface Settings {
  backend: string;
  backends: string[];
  isLocal: boolean;
  loadedModel: string;
  remoteApiUrl: string;
  remoteModelName: string;
  hasApiKey: boolean;
  contextSize: number;
  generation: Gen;
}

export function SettingsPage() {
  const [s, setS] = useState<Settings | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  const [testing, setTesting] = useState(false);
  const [testMsg, setTestMsg] = useState('');

  const load = () => api.get<Settings>('/api/settings').then(setS).catch(() => {});
  useEffect(() => {
    void load();
  }, []);

  if (!s) return <div className="centered"><div className="spinner" /></div>;

  const patch = (p: Partial<Settings>) => setS({ ...s, ...p });
  const patchGen = (p: Partial<Gen>) => setS({ ...s, generation: { ...s.generation, ...p } });

  const save = async () => {
    setSaving(true);
    setError('');
    setSaved(false);
    try {
      const body: Record<string, unknown> = {
        backend: s.backend,
        remoteApiUrl: s.remoteApiUrl,
        remoteModelName: s.remoteModelName,
        generation: s.generation,
      };
      if (apiKey.trim()) body.apiKey = apiKey.trim();
      const next = await api.post<Settings>('/api/settings', body);
      setS(next);
      setApiKey('');
      setSaved(true);
      setTimeout(() => setSaved(false), 1800);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save settings');
    } finally {
      setSaving(false);
    }
  };

  // Which unified backend option is active: local backends map 1:1; the
  // OpenAI-compatible "openRouter" backend is disambiguated by its saved URL
  // (Nano-GPT / OpenRouter / else Custom).
  const currentBackendId = (): string => {
    if (s.backend !== 'openRouter') return s.backend;
    const match = BACKEND_OPTIONS.find(
      (o) => o.backend === 'openRouter' && o.url && o.url === s.remoteApiUrl.trim(),
    );
    return match ? match.id : 'custom';
  };

  // Switching backend sets the BackendType and, for fixed-URL providers, the API
  // URL; Custom clears the URL so it doesn't masquerade as a named provider and
  // the model dropdown refetches off the new endpoint.
  const onBackendChange = (id: string) => {
    const opt = BACKEND_OPTIONS.find((o) => o.id === id);
    if (!opt) return;
    const next: Partial<Settings> = { backend: opt.backend };
    if (id === 'custom') next.remoteApiUrl = '';
    else if (opt.url) next.remoteApiUrl = opt.url;
    patch(next);
  };

  const testConnection = async () => {
    setTesting(true);
    setTestMsg('');
    try {
      const body: Record<string, unknown> = { apiUrl: s.remoteApiUrl };
      if (apiKey.trim()) body.apiKey = apiKey.trim();
      const r = await api.post<{ ok: boolean; message: string }>('/api/backend/test-connection', body);
      setTestMsg(r.message);
    } catch (e) {
      setTestMsg(e instanceof ApiError ? e.message : 'Connection test failed');
    } finally {
      setTesting(false);
    }
  };

  // Control visibility keys off the *selected* backend so it updates the instant
  // the dropdown changes (before saving). Local backends are host subprocesses;
  // the API ones connect to an OpenAI-compatible server.
  const selectedId = currentBackendId();
  const isApi = s.backend === 'openRouter' || s.backend === 'omlx';
  const isManagedLocal = s.backend === 'kobold' || s.backend === 'pseudoRemote';
  const showUrlField = selectedId === 'custom'; // named providers + oMLX have fixed URLs
  const showKeyField = s.backend === 'openRouter'; // oMLX is local — no key

  return (
    <div className="page">
      <h2>Settings</h2>

      <PersonaManager />

      <section className="card">
        <h3>Model &amp; backend</h3>
        <label>
          Backend
          <select value={selectedId} onChange={(e) => onBackendChange(e.target.value)}>
            {BACKEND_OPTIONS.map((o) => (
              <option key={o.id} value={o.id}>{o.label}</option>
            ))}
          </select>
        </label>
        <p className="muted small">Loaded model: <strong>{s.loadedModel}</strong> · context {s.contextSize}</p>

        {isManagedLocal && (
          <p className="muted small">
            This backend runs on the host machine. Pick or download its model on the Models tab;
            GPU and launch options are configured in the desktop app.
          </p>
        )}

        {isApi && (
          <>
            {showUrlField && (
              <label>
                API URL
                <input
                  value={s.remoteApiUrl}
                  onChange={(e) => patch({ remoteApiUrl: e.target.value })}
                  placeholder="https://your-server.example/v1"
                />
              </label>
            )}
            <label>
              Model
              <ModelPicker
                apiUrl={s.remoteApiUrl}
                apiKey={apiKey}
                value={s.remoteModelName}
                onChange={(id) => patch({ remoteModelName: id })}
              />
            </label>
            {showKeyField && (
              <label>
                API key
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  placeholder={s.hasApiKey ? '•••••• (leave blank to keep)' : 'paste your API key'}
                />
              </label>
            )}
            <div className="test-conn-row">
              <button className="ghost" onClick={testConnection} disabled={testing}>
                {testing ? 'Testing…' : 'Test connection'}
              </button>
              {testMsg && (
                <span className={`test-conn-msg${testMsg.toLowerCase().includes('success') ? ' ok' : ' bad'}`}>
                  {testMsg}
                </span>
              )}
            </div>
          </>
        )}
      </section>

      <section className="card">
        <h3>Generation</h3>
        <NumberField label="Temperature" value={s.generation.temperature} step={0.05} min={0} max={2}
          onChange={(v) => patchGen({ temperature: v })} />
        <NumberField label="Min-P" value={s.generation.minP} step={0.01} min={0} max={1}
          onChange={(v) => patchGen({ minP: v })} />
        <NumberField label="Repeat penalty" value={s.generation.repeatPenalty} step={0.01} min={1} max={1.5}
          onChange={(v) => patchGen({ repeatPenalty: v })} />
        <NumberField label="Response length (max tokens)" value={s.generation.maxLength} step={8} min={16} max={2048}
          onChange={(v) => patchGen({ maxLength: Math.round(v) })} />
        <NumberField label="Min length" value={s.generation.minLength} step={1} min={0} max={512}
          onChange={(v) => patchGen({ minLength: Math.round(v) })} />
        <label className="row-label">
          <span>Dynamic temperature</span>
          <input
            type="checkbox"
            checked={s.generation.dynamicTempEnabled}
            onChange={(e) => patchGen({ dynamicTempEnabled: e.target.checked })}
          />
        </label>
      </section>

      {error && <p className="error">{error}</p>}
      <button className="primary" onClick={save} disabled={saving}>
        {saving ? 'Saving…' : saved ? 'Saved ✓' : 'Save settings'}
      </button>
    </div>
  );
}

function NumberField({
  label,
  value,
  step,
  min,
  max,
  onChange,
}: {
  label: string;
  value: number;
  step: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
}) {
  return (
    <label>
      {label}
      <input
        type="number"
        value={value}
        step={step}
        min={min}
        max={max}
        onChange={(e) => {
          const n = Number(e.target.value);
          if (Number.isFinite(n)) onChange(n);
        }}
      />
    </label>
  );
}
