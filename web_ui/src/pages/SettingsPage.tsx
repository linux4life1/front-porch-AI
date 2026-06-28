// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { PersonaManager } from '../components/PersonaManager';
import { ModelPicker } from '../components/ModelPicker';
import { ChatColorsSettings } from '../components/ChatColorsSettings';

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
  repeatPenaltyTokens: number;
  xtcThreshold: number;
  xtcProbability: number;
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
  reasoningEnabled: boolean;
  reasoningEffort: string;
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
        contextSize: s.contextSize,
        reasoningEnabled: s.reasoningEnabled,
        reasoningEffort: s.reasoningEffort,
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

      <ChatColorsSettings />

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
        <SliderField label="Temperature" value={s.generation.temperature} min={0} max={2} step={0.05}
          onChange={(v) => patchGen({ temperature: v })} />
        <SliderField label="Min-P" value={s.generation.minP} min={0} max={1} step={0.01}
          onChange={(v) => patchGen({ minP: v })} />
        <SliderField label="Repeat penalty" value={s.generation.repeatPenalty} min={1} max={3} step={0.01}
          onChange={(v) => patchGen({ repeatPenalty: v })} />
        <SliderField label="Rep pen tokens" value={s.generation.repeatPenaltyTokens} min={0} max={512} step={1}
          onChange={(v) => patchGen({ repeatPenaltyTokens: Math.round(v) })} />
        <SliderField label="XTC threshold" value={s.generation.xtcThreshold} min={0} max={0.5} step={0.01}
          onChange={(v) => patchGen({ xtcThreshold: v })} />
        <SliderField label="XTC probability" value={s.generation.xtcProbability} min={0} max={1} step={0.05}
          onChange={(v) => patchGen({ xtcProbability: v })} />
        <SliderField label="Max output tokens" value={s.generation.maxLength} min={16} max={16384} step={16}
          onChange={(v) => patchGen({ maxLength: Math.round(v) })} />
        <SliderField label="Min output tokens" value={s.generation.minLength} min={0} max={512} step={1}
          onChange={(v) => patchGen({ minLength: Math.round(v) })} />
        <SliderField label="Context size" value={s.contextSize} min={512} max={500000} step={512}
          onChange={(v) => patch({ contextSize: Math.round(v) })} />
        <label className="row-label">
          <span>Dynamic temperature</span>
          <input
            type="checkbox"
            checked={s.generation.dynamicTempEnabled}
            onChange={(e) => patchGen({ dynamicTempEnabled: e.target.checked })}
          />
        </label>
        <label className="row-label">
          <span>Reasoning / thinking</span>
          <input
            type="checkbox"
            checked={s.reasoningEnabled}
            onChange={(e) => patch({ reasoningEnabled: e.target.checked })}
          />
        </label>
        {s.reasoningEnabled && (
          <label>
            Reasoning effort
            <select value={s.reasoningEffort} onChange={(e) => patch({ reasoningEffort: e.target.value })}>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
            </select>
          </label>
        )}
        <p className="muted small">
          Turn on for reasoning models (e.g. GLM-*:thinking) so their thinking is captured and shown
          as a collapsible block under each reply. Off discards the reasoning.
        </p>
      </section>

      {error && <p className="error">{error}</p>}
      <button className="primary" onClick={save} disabled={saving}>
        {saving ? 'Saving…' : saved ? 'Saved ✓' : 'Save settings'}
      </button>
    </div>
  );
}

// A labelled slider with an editable value box (mirrors the desktop sampler
// sliders): label + value on top, range below; the box accepts exact typing.
function SliderField({
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
    <div className="slider-field">
      <div className="slider-head">
        <span>{label}</span>
        <input
          type="number"
          className="slider-val"
          value={value}
          step={step}
          min={min}
          max={max}
          onChange={(e) => {
            const n = Number(e.target.value);
            if (Number.isFinite(n)) onChange(n);
          }}
        />
      </div>
      <input
        type="range"
        value={value}
        step={step}
        min={min}
        max={max}
        onChange={(e) => onChange(Number(e.target.value))}
      />
    </div>
  );
}
