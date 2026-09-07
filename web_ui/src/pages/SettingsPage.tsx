// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { PersonaManager } from '../components/PersonaManager';
import { ModelPicker } from '../components/ModelPicker';
import { ChatColorsSettings } from '../components/ChatColorsSettings';
import { PorchLifeSettings } from '../components/PorchLifeSettings';
import { ModelTransportCard } from '../components/ModelTransportCard';
import { applySpellCheckLang } from '../spellCheckLang';
import {
  StepUpFields,
  attachStepUp,
  remotePreviewNeedsStepUp,
} from '../components/StepUpFields';
import {
  GenerationSettingsFields,
  type GenSettings,
} from '../components/GenerationSettingsFields';
import { VoiceMediaSettings } from '../components/VoiceMediaSettings';

// A single backend picker (replacing the old Backend + Provider dropdowns,
// which overlapped). Each entry maps to a real BackendType; the OpenAI-compatible
// providers are first-class so the user chooses "where generation happens" once.
// `url` (when present) is the fixed API base for that provider — selecting it
// fills remoteApiUrl. `kind` drives which controls show:
//   local — host subprocess (KoboldCpp, optionally from a .kcpps preset): managed on the host.
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
  { id: 'omlx', label: 'oMLX (local API)', backend: 'omlx', url: 'http://localhost:8000/v1', kind: 'api' },
  { id: 'nanogpt', label: 'Nano-GPT', backend: 'openRouter', url: 'https://nano-gpt.com/api/v1', kind: 'api' },
  { id: 'openrouter', label: 'OpenRouter', backend: 'openRouter', url: 'https://openrouter.ai/api/v1', kind: 'api' },
  { id: 'custom', label: 'Custom API (OpenAI-compatible)', backend: 'openRouter', url: '', kind: 'api' },
];

type Gen = GenSettings;
interface Settings {
  backend: string;
  backends: string[];
  isLocal: boolean;
  loadedModel: string;
  remoteApiUrl: string;
  remoteModelName: string;
  hasApiKey: boolean;
  remoteConfigured?: boolean;
  remoteReachability?: 'unknown' | 'checking' | 'reachable' | 'unreachable';
  contextSize: number;
  reasoningEnabled: boolean;
  reasoningEffort: string;
  reasoningMandatory?: boolean;
  reasoningEfforts?: string[];
  // KoboldCpp / oMLX / LM Studio template verdict: what this model actually
  // supports — 'graded' | 'toggle' | 'always' | 'none'. Absent on remote
  // hosted backends and until the template has been read, which is the
  // signal to fall back to the generic chips instead of claiming knowledge
  // we do not have.
  reasoningLocalSupport?: string;
  generation: Gen;
  /** Dictionary tag ('en_US') or 'off'. Optional for the same reason. */
  spellCheckLanguage?: string;
  /** Dictionary tags the host can check. Optional for the same reason. */
  spellCheckLanguages?: string[];
  systemPrompt?: string;
  bannedPhrases?: string[];
}

// Legacy-engine model files still on the host (desktop parity: the Reclaim
// Disk Space card in Settings → Voice & Media). Absent/empty → no section.
interface LegacyModels {
  groups: { label: string; bytes: number }[];
  totalBytes: number;
}

const fmtBytes = (b: number) =>
  b >= 1024 ** 3 ? `${(b / 1024 ** 3).toFixed(1)} GB` : `${Math.round(b / 1024 ** 2)} MB`;

function remoteReachabilityLabel(
  configured: boolean,
  reachability?: string,
): { text: string; tone: 'ok' | 'busy' | 'down' | 'configured' } {
  if (!configured) return { text: 'Not configured', tone: 'down' };
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

function RemoteReachabilityBadge({
  configured,
  reachability,
}: {
  configured: boolean;
  reachability?: string;
}) {
  const { text, tone } = remoteReachabilityLabel(configured, reachability);
  return (
    <span className={`remote-ready-badge remote-ready-badge-${tone}`}>
      <span className="engine-dot" />
      {text}
    </span>
  );
}

export function SettingsPage() {
  const [s, setS] = useState<Settings | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  const [testing, setTesting] = useState(false);
  const [testMsg, setTestMsg] = useState('');

  const [legacy, setLegacy] = useState<LegacyModels | null>(null);
  const [reclaiming, setReclaiming] = useState(false);
  const [savedRemoteApiUrl, setSavedRemoteApiUrl] = useState('');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);

  const load = () =>
    api
      .get<Settings>('/api/settings')
      .then((next) => {
        setS(next);
        setSavedRemoteApiUrl(next.remoteApiUrl);
      })
      .catch(() => {});
  const loadLegacy = () =>
    api.get<LegacyModels>('/api/legacy-models').then(setLegacy).catch(() => {});
  useEffect(() => {
    void load();
    void loadLegacy();
    void api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((st) => setTotpEnabled(!!st.totpEnabled))
      .catch(() => {});
  }, []);

  const reclaim = async () => {
    if (
      !window.confirm(
        'Permanently delete the old speech engines’ model files? ' +
          'Your voices and settings are unaffected — the new engines ' +
          'have their own models.',
      )
    )
      return;
    setReclaiming(true);
    try {
      await api.post('/api/legacy-models/reclaim');
      await loadLegacy();
    } catch {
      /* surfaced by the section simply not shrinking */
    } finally {
      setReclaiming(false);
    }
  };

  if (!s) return <div className="centered"><div className="spinner" /></div>;

  const patch = (p: Partial<Settings>) =>
    setS((prev) => (prev ? { ...prev, ...p } : prev));
  const patchGen = (p: Partial<Gen>) =>
    setS((prev) =>
      prev ? { ...prev, generation: { ...prev.generation, ...p } } : prev,
    );

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
        systemPrompt: s.systemPrompt,
        bannedPhrases: s.bannedPhrases,
      };
      if (s.spellCheckLanguage !== undefined) {
        body.spellCheckLanguage = s.spellCheckLanguage;
      }
      if (apiKey.trim()) body.apiKey = apiKey.trim();
      const needsStepUp =
        s.remoteApiUrl !== savedRemoteApiUrl || !!apiKey.trim();
      if (needsStepUp) {
        attachStepUp(body, password, totpEnabled, totpCode);
      }
      const next = await api.post<Settings>('/api/settings', body);
      setS(next);
      setSavedRemoteApiUrl(next.remoteApiUrl);
      // Take effect on this device immediately rather than at next reload.
      applySpellCheckLang(next.spellCheckLanguage);
      setApiKey('');
      setPassword('');
      setTotpCode('');
      setSaved(true);
      setTimeout(() => setSaved(false), 1800);
    } catch (e) {
      if (e instanceof ApiError && e.payload.totpRequired === true) {
        setTotpEnabled(true);
      }
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

  const previewNeedsStepUp = remotePreviewNeedsStepUp(
    s.remoteApiUrl,
    apiKey,
    savedRemoteApiUrl,
  );

  const testConnection = async () => {
    setTesting(true);
    setTestMsg('');
    try {
      const body: Record<string, unknown> = { apiUrl: s.remoteApiUrl };
      if (apiKey.trim()) body.apiKey = apiKey.trim();
      if (previewNeedsStepUp) {
        attachStepUp(body, password, totpEnabled, totpCode);
      }
      const r = await api.post<{ ok: boolean; message: string }>('/api/backend/test-connection', body);
      setTestMsg(r.message);
    } catch (e) {
      if (e instanceof ApiError && e.payload.totpRequired === true) {
        setTotpEnabled(true);
      }
      setTestMsg(e instanceof ApiError ? e.message : 'Connection test failed');
    } finally {
      setTesting(false);
      void load();
    }
  };

  // Control visibility keys off the *selected* backend so it updates the instant
  // the dropdown changes (before saving). Local backends are host subprocesses;
  // the API ones connect to an OpenAI-compatible server.
  const selectedId = currentBackendId();
  const isApi = s.backend === 'openRouter' || s.backend === 'omlx';
  const isManagedLocal = s.backend === 'kobold';
  const showUrlField = selectedId === 'custom'; // named providers + oMLX have fixed URLs
  const showKeyField = s.backend === 'openRouter'; // oMLX is local — no key

  return (
    <div className="page">
      <h2>Settings</h2>

      <PersonaManager />

      <ChatColorsSettings />

      <PorchLifeSettings />

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
                savedApiUrl={savedRemoteApiUrl}
                currentPassword={password}
                totpCode={totpCode}
                totpEnabled={totpEnabled}
                onTotpRequired={() => setTotpEnabled(true)}
                value={s.remoteModelName}
                onChange={(id) => {
                  patch({ remoteModelName: id })
                  void (async () => {
                    if (previewNeedsStepUp && !password) return
                    try {
                      const body: Record<string, unknown> = {
                        model: id,
                        apiUrl: s.remoteApiUrl,
                      }
                      if (apiKey.trim()) body.apiKey = apiKey.trim()
                      if (previewNeedsStepUp) {
                        attachStepUp(body, password, totpEnabled, totpCode)
                      }
                      const menu = await api.post<{
                        efforts?: string[]
                        mandatory?: boolean
                        localSupport?: string
                      }>('/api/backend/reasoning-menu', body)
                      setS((prev) =>
                        prev && prev.remoteModelName === id
                          ? {
                              ...prev,
                              reasoningEfforts: menu.efforts ?? [],
                              reasoningMandatory: Boolean(menu.mandatory),
                              reasoningLocalSupport: menu.localSupport,
                            }
                          : prev,
                      )
                    } catch (e) {
                      if (e instanceof ApiError && e.payload.totpRequired === true) {
                        setTotpEnabled(true)
                      }
                      /* family-hint chips stay until Save */
                    }
                  })()
                }}
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
              <RemoteReachabilityBadge
                configured={s.remoteConfigured ?? s.hasApiKey}
                reachability={s.remoteReachability}
              />
              <button
                className="ghost"
                onClick={testConnection}
                disabled={testing || (previewNeedsStepUp && !password)}
              >
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

      <GenerationSettingsFields
        backend={s.backend}
        isLocal={s.isLocal}
        remoteModelName={s.remoteModelName}
        contextSize={s.contextSize}
        generation={s.generation}
        systemPrompt={s.systemPrompt}
        bannedPhrases={s.bannedPhrases}
        spellCheckLanguage={s.spellCheckLanguage}
        spellCheckLanguages={s.spellCheckLanguages}
        reasoningEnabled={s.reasoningEnabled}
        reasoningEffort={s.reasoningEffort}
        reasoningMandatory={s.reasoningMandatory}
        reasoningEfforts={s.reasoningEfforts}
        reasoningLocalSupport={s.reasoningLocalSupport}
        patch={(p) => patch(p as Partial<Settings>)}
        patchGen={patchGen}
      />

      {/* Moved out of the Porch Life card so the switch sits under
          Generation on both surfaces (desktop parity). */}
      <ModelTransportCard />

      <VoiceMediaSettings />

      {legacy && legacy.totalBytes > 0 && (
        <section className="card">
          <h3>Reclaim disk space</h3>
          <p className="muted small">
            The new built-in speech engines use their own models. These files
            from the old engines are no longer used:
          </p>
          {legacy.groups.map((g) => (
            <p key={g.label} className="muted small" style={{ margin: '4px 0' }}>
              • {g.label} — {fmtBytes(g.bytes)}
            </p>
          ))}
          <button className="ghost" onClick={() => void reclaim()} disabled={reclaiming}>
            {reclaiming ? 'Reclaiming…' : `Reclaim ${fmtBytes(legacy.totalBytes)}`}
          </button>
        </section>
      )}

      {error && <p className="error">{error}</p>}
      {(s.remoteApiUrl !== savedRemoteApiUrl || !!apiKey.trim()) && (
        <StepUpFields
          password={password}
          onPassword={setPassword}
          totpEnabled={totpEnabled}
          totpCode={totpCode}
          onTotp={setTotpCode}
          reason={
            totpEnabled
              ? 'Changing the API URL or key — or testing a new host — needs your web login password and a 2FA code.'
              : 'Changing the API URL or key — or testing a new host — needs your web login password.'
          }
        />
      )}
      <button
        className="primary"
        onClick={save}
        disabled={
          saving ||
          ((s.remoteApiUrl !== savedRemoteApiUrl || !!apiKey.trim()) && !password)
        }
      >
        {saving ? 'Saving…' : saved ? 'Saved ✓' : 'Save settings'}
      </button>

      <section className="card">
        <h2>About &amp; License</h2>
        <p className="muted small" style={{ lineHeight: 1.5 }}>
          Front Porch AI is free, open-source software © 2026 Front Porch AI,
          licensed under the GNU Affero General Public License v3.0. You are
          free to use, study, modify, and redistribute it under the AGPL. The
          complete source code is available below; if you received this app
          without that source, or as part of a closed-source product, that is a
          license violation.
        </p>
        <div className="about-links">
          <a
            className="btn-link"
            href="https://github.com/linux4life1/front-porch-ai"
            target="_blank"
            rel="noopener noreferrer"
          >
            Source code
          </a>
          <a
            className="btn-link"
            href="https://github.com/linux4life1/front-porch-ai/issues"
            target="_blank"
            rel="noopener noreferrer"
          >
            Report a license violation
          </a>
        </div>
      </section>
    </div>
  );
}
