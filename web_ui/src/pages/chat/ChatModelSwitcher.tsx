// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-chat model chip. Desktop opens the global Model Settings dialog from the
// chat sidebar (lib/ui/pages/chat_page.sidebar_widgets.dart) — one
// remoteModelName for every chat, not a per-chat override. This chip writes
// that same field through POST /api/settings. A model-only body does not
// change the API URL or key, so it does not need the password step-up Settings
// uses for those. If the server asks for one anyway, the sheet says so and
// links to Settings instead of failing quietly.
//
// The sheet also switches provider, like the desktop Model Settings dialog.
// A provider with a different API URL is a credential-grade write, so the
// sheet asks for the web login password inline (same rule as Settings) —
// picking a model on the current provider never does.
//
// KoboldCpp (and any other backend ModelPicker does not apply to) has no
// remote model list. The chip shows the backend name and the sheet links to
// Settings, where the host model is chosen. The Settings links replace the
// sheet's history marker entry, so Back from Settings lands on the chat.

import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, ApiError } from '../../api/client';
import { ModelPicker } from '../../components/ModelPicker';
import { attachStepUp, StepUpFields } from '../../components/StepUpFields';
import { useBackDismiss } from '../../hooks/useBackDismiss';
import { BACKEND_OPTIONS, backendOptionId } from '../../backendOptions';
import { urlHasStoredApiKey } from '../../remoteApiKeys';

const MARKER_KEY = 'fpModelSwitch';
/** Hosted providers that cannot list models without a saved key. */
const KEYED_PROVIDERS = new Set(['openrouter', 'nanogpt', 'xai']);

export interface ChatModelSnapshot {
  backend: string;
  remoteApiUrl: string;
  remoteModelName: string;
  loadedModel?: string;
  remoteApiUrlsWithKeys?: string[];
  omlxAvailable?: boolean;
}

const BACKEND_LABELS: Record<string, string> = {
  kobold: 'KoboldCpp',
  omlx: 'oMLX',
  openRouter: 'Remote API',
};

/** ModelPicker is the chat-model control for OpenAI-compatible backends only. */
export function modelPickerApplies(backend: string): boolean {
  return backend === 'openRouter' || backend === 'omlx';
}

export function backendDisplayName(backend: string): string {
  const known = BACKEND_LABELS[backend];
  if (known) return known;
  const trimmed = backend.trim();
  return trimmed || 'Model';
}

export function chatModelChipLabel(s: ChatModelSnapshot): string {
  if (modelPickerApplies(s.backend)) {
    const name = s.remoteModelName.trim();
    return name || 'Select a model';
  }
  return backendDisplayName(s.backend);
}

function pinVisualViewport(el: HTMLElement): () => void {
  const vv = window.visualViewport;
  if (!vv) return () => {};
  const apply = () => {
    el.style.setProperty('--fp-vvh', `${vv.height}px`);
    el.style.setProperty('--fp-vvw', `${vv.width}px`);
    el.style.setProperty('--fp-vv-top', `${vv.offsetTop}px`);
    el.style.setProperty('--fp-vv-left', `${vv.offsetLeft}px`);
  };
  apply();
  vv.addEventListener('resize', apply);
  vv.addEventListener('scroll', apply);
  window.addEventListener('scroll', apply);
  return () => {
    vv.removeEventListener('resize', apply);
    vv.removeEventListener('scroll', apply);
    window.removeEventListener('scroll', apply);
    el.style.removeProperty('--fp-vvh');
    el.style.removeProperty('--fp-vvw');
    el.style.removeProperty('--fp-vv-top');
    el.style.removeProperty('--fp-vv-left');
  };
}

function ModelSwitchSheet({
  settings,
  onClose,
  onSaved,
}: {
  settings: ChatModelSnapshot;
  onClose: () => void;
  /** keepOpen: a host-local provider was saved; list its models next. */
  onSaved: (next: ChatModelSnapshot, keepOpen?: boolean) => void;
}) {
  const overlayRef = useRef<HTMLDivElement>(null);
  const [error, setError] = useState('');
  const [needsSettings, setNeedsSettings] = useState(false);
  const [saving, setSaving] = useState(false);
  const alive = useRef(true);
  const requestDismiss = useBackDismiss(MARKER_KEY, onClose);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  useLayoutEffect(() => {
    const el = overlayRef.current;
    if (!el) return;
    return pinVisualViewport(el);
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      e.preventDefault();
      e.stopPropagation();
      requestDismiss();
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [requestDismiss]);

  const savedId = backendOptionId(settings.backend, settings.remoteApiUrl);
  const [providerId, setProviderId] = useState(savedId);
  const [password, setPassword] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);
  const [totpCode, setTotpCode] = useState('');
  const provider = BACKEND_OPTIONS.find((o) => o.id === providerId) ?? BACKEND_OPTIONS[0];
  const switching = providerId !== savedId;
  // KoboldCpp has no remote URL; leaving it untouched keeps that switch
  // out of the credential step-up.
  const draftUrl =
    switching && provider.kind === 'api' ? (provider.url ?? '') : settings.remoteApiUrl;
  const urlChanges = draftUrl.trim() !== settings.remoteApiUrl.trim();
  // The server will not preview an unsaved localhost URL (SSRF gate), so
  // LM Studio / oMLX are saved first and listed from the stored URL after.
  const hostLocal = switching && /^https?:\/\/(localhost|127\.0\.0\.1)[:/]/i.test(draftUrl);
  const canPick = switching
    ? provider.kind === 'api' && provider.id !== 'custom' && !hostLocal
    : modelPickerApplies(settings.backend);
  const missingKey =
    canPick &&
    KEYED_PROVIDERS.has(provider.id) &&
    !urlHasStoredApiKey(draftUrl, settings.remoteApiUrlsWithKeys);
  const providers = BACKEND_OPTIONS.filter(
    (o) => o.id !== 'omlx' || settings.omlxAvailable === true || savedId === 'omlx',
  );

  const post = (body: Record<string, unknown>, fallbackModel: string, keepOpen = false) => {
    if (saving) return;
    setSaving(true);
    setError('');
    setNeedsSettings(false);
    void (async () => {
      try {
        const next = await api.post<ChatModelSnapshot>('/api/settings', body);
        onSaved(
          {
            ...settings,
            ...next,
            remoteModelName: next.remoteModelName || fallbackModel,
          },
          keepOpen,
        );
        if (keepOpen && alive.current) setSaving(false);
      } catch (e) {
        if (!alive.current) return;
        setSaving(false);
        if (e instanceof ApiError && e.payload.totpRequired === true) {
          if (urlChanges) {
            setTotpEnabled(true);
            setError('Enter your two-factor code to switch provider.');
            return;
          }
          setNeedsSettings(true);
          setError('Saving the model needs your web login. Open Settings to confirm it.');
          return;
        }
        setError(e instanceof ApiError ? e.message : 'Could not save the model');
      }
    })();
  };

  const save = (id: string) => {
    const body: Record<string, unknown> = { remoteModelName: id };
    if (switching) body.backend = provider.backend;
    if (urlChanges) {
      body.remoteApiUrl = draftUrl;
      attachStepUp(body, password, totpEnabled, totpCode);
    }
    post(body, id);
  };

  const switchHost = () => {
    const body: Record<string, unknown> = { backend: provider.backend };
    if (urlChanges) {
      body.remoteApiUrl = draftUrl;
      body.remoteModelName = '';
      attachStepUp(body, password, totpEnabled, totpCode);
    }
    post(body, '', provider.kind === 'api');
  };

  const pickProvider = (id: string) => {
    setProviderId(id);
    setError('');
    setNeedsSettings(false);
  };

  return (
    <div
      className="drawer-backdrop center model-switch-overlay"
      ref={overlayRef}
      onClick={requestDismiss}
    >
      <div
        className="modal model-switch-sheet"
        role="dialog"
        aria-label="Change model"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="model-switch-head">
          <span className="model-switch-title">Model</span>
          <button type="button" className="ghost" onClick={requestDismiss}>
            Close
          </button>
        </div>
        <div className="model-switch-body">
          <label className="model-switch-provider">
            Provider
            <select value={providerId} onChange={(e) => pickProvider(e.target.value)}>
              {providers.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </select>
          </label>
          {(canPick || hostLocal) && urlChanges && (
            <StepUpFields
              password={password}
              onPassword={setPassword}
              totpEnabled={totpEnabled}
              totpCode={totpCode}
              onTotp={setTotpCode}
              reason={`Switching to ${provider.label} changes where your chats are sent. Confirm with your web login password.`}
            />
          )}
          {missingKey && (
            <p className="muted small">
              No API key is saved for {provider.label} yet.{' '}
              <Link to="/settings" replace>
                Add it in Settings
              </Link>
            </p>
          )}
          {canPick ? (
            <ModelPicker
              key={providerId}
              apiUrl={urlChanges ? draftUrl : ''}
              apiKey=""
              savedApiUrl={settings.remoteApiUrl}
              currentPassword={urlChanges ? password : ''}
              totpCode={totpCode}
              totpEnabled={totpEnabled}
              onTotpRequired={() => setTotpEnabled(true)}
              value={switching ? '' : settings.remoteModelName}
              onChange={save}
            />
          ) : switching && (provider.kind === 'local' || hostLocal) ? (
            <>
              <p className="muted small">
                {provider.label} runs on the computer that hosts this chat.
                {provider.kind === 'local'
                  ? ' Its model is chosen in Settings.'
                  : ' Switch first, then pick its model here.'}
              </p>
              <button
                type="button"
                className="primary"
                disabled={saving || (urlChanges && !password.trim())}
                onClick={switchHost}
              >
                Switch to {provider.label}
              </button>
            </>
          ) : switching ? (
            <>
              <p className="muted small">A custom provider address is set in Settings.</p>
              <Link to="/settings" replace className="model-switch-settings">
                Open Settings
              </Link>
            </>
          ) : (
            <>
              <p className="muted small">
                {backendDisplayName(settings.backend)} runs on the computer that hosts
                this chat. Choose its model in Settings.
              </p>
              <Link to="/settings" replace className="model-switch-settings">
                Open Settings
              </Link>
            </>
          )}
          {saving && <p className="muted small">Saving…</p>}
          {error && (
            <p className="error" role="alert">
              {error}{' '}
              {needsSettings && <Link to="/settings" replace>
                  Open Settings
                </Link>}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

export function ChatModelSwitcher() {
  const [settings, setSettings] = useState<ChatModelSnapshot | null>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    api
      .get<ChatModelSnapshot>('/api/settings')
      .then((next) => {
        if (!cancelled) setSettings(next);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  if (!settings) return null;

  const label = chatModelChipLabel(settings);

  return (
    <>
      <button
        type="button"
        className="model-switch-chip"
        title={label}
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen(true)}
      >
        <span className="model-switch-chip-text">{label}</span>
      </button>
      {open && (
        <ModelSwitchSheet
          settings={settings}
          onClose={() => setOpen(false)}
          onSaved={(next, keepOpen) => {
            setSettings(next);
            if (!keepOpen) setOpen(false);
          }}
        />
      )}
    </>
  );
}
