// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { PersonaManager } from '../components/PersonaManager';

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

        {!s.isLocal && (
          <>
            <label>
              API URL
              <input
                value={s.remoteApiUrl}
                onChange={(e) => patch({ remoteApiUrl: e.target.value })}
                placeholder="https://openrouter.ai/api/v1"
              />
            </label>
            <label>
              Model name
              <input
                value={s.remoteModelName}
                onChange={(e) => patch({ remoteModelName: e.target.value })}
                placeholder="e.g. anthropic/claude-3.5-sonnet"
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
