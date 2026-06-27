// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { PersonaManager } from '../components/PersonaManager';
import { ModelPicker } from '../components/ModelPicker';

// Provider presets auto-fill the API URL for the common OpenAI-compatible
// backends. "Custom" leaves the URL free for anything else (vLLM, LM Studio…).
const PROVIDER_PRESETS: { id: string; label: string; url: string }[] = [
  { id: 'nanogpt', label: 'Nano-GPT', url: 'https://nano-gpt.com/api/v1' },
  { id: 'openrouter', label: 'OpenRouter', url: 'https://openrouter.ai/api/v1' },
  { id: 'omlx', label: 'oMLX (local)', url: 'http://localhost:8000/v1' },
  { id: 'custom', label: 'Custom', url: '' },
];
const presetForUrl = (url: string): string =>
  PROVIDER_PRESETS.find((p) => p.url && p.url === url.trim())?.id ?? 'custom';

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

const BACKEND_LABELS: Record<string, string> = {
  kobold: 'KoboldCpp (local)',
  pseudoRemote: 'Pseudo-Remote (local server)',
  openRouter: 'OpenRouter / API',
  omlx: 'oMLX (local)',
};

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

  // Selecting a provider preset just fills the API URL (Custom clears it for
  // free entry). The model dropdown refetches off the new URL automatically.
  const onPreset = (id: string) => {
    const preset = PROVIDER_PRESETS.find((p) => p.id === id);
    if (!preset) return;
    if (id === 'custom') return; // keep the current URL editable
    patch({ remoteApiUrl: preset.url });
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

  // Only KoboldCpp is "local" with no remote endpoint; openRouter / pseudoRemote
  // / oMLX all use an OpenAI-compatible URL + model. Gate the remote controls on
  // the *selected* backend (not the saved one) so they appear the moment you
  // switch the dropdown, before saving.
  const isRemoteSel = s.backend !== 'kobold';

  return (
    <div className="page">
      <h2>Settings</h2>

      <PersonaManager />

      <section className="card">
        <h3>Model &amp; backend</h3>
        <label>
          Backend
          <select value={s.backend} onChange={(e) => patch({ backend: e.target.value })}>
            {s.backends.map((b) => (
              <option key={b} value={b}>{BACKEND_LABELS[b] ?? b}</option>
            ))}
          </select>
        </label>
        <p className="muted small">Loaded model: <strong>{s.loadedModel}</strong> · context {s.contextSize}</p>

        {isRemoteSel && (
          <>
            <label>
              Provider
              <select
                value={presetForUrl(s.remoteApiUrl)}
                onChange={(e) => onPreset(e.target.value)}
                aria-label="Provider preset"
              >
                {PROVIDER_PRESETS.map((p) => (
                  <option key={p.id} value={p.id}>{p.label}</option>
                ))}
              </select>
            </label>
            <label>
              API URL
              <input
                value={s.remoteApiUrl}
                onChange={(e) => patch({ remoteApiUrl: e.target.value })}
                placeholder="https://openrouter.ai/api/v1"
              />
            </label>
            <label>
              Model
              <ModelPicker
                apiUrl={s.remoteApiUrl}
                apiKey={apiKey}
                value={s.remoteModelName}
                onChange={(id) => patch({ remoteModelName: id })}
              />
            </label>
            <label>
              API key
              <input
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder={s.hasApiKey ? '•••••• (leave blank to keep)' : 'paste your API key'}
              />
            </label>
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
