// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Realism evals inside the chat Model sheet (docs/design/one-chat-ux.md
// PR 6): the WorkerBackendCard the desktop Model Settings dialog embeds,
// live-saved through POST /api/settings like the dialog writes straight to
// storage. The server gates helper writes credential-grade
// (lib/services/web/routes/settings_routes.dart): a changed helper URL, a
// typed API key, or a changed evals GGUF / .kcpps path need the web login
// password. Those changes are held in the draft until the password is
// entered, then flushed — the sheet's own provider-switch pattern.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../../api/client';
import { WorkerBackendCard, type WorkerBackendFields } from '../../components/WorkerBackendCard';
import { attachStepUp, StepUpFields } from '../../components/StepUpFields';

const WORKER_KEYS = [
  'workerBackend',
  'workerRemoteApiUrl',
  'workerRemoteModelName',
  'workerKoboldModelPath',
  'workerKoboldKcppsPath',
] as const;

function bodyFor(
  draft: Partial<WorkerBackendFields>,
  workerApiKey: string,
): Record<string, unknown> {
  const body: Record<string, unknown> = {};
  for (const key of WORKER_KEYS) {
    if (key in draft) body[key] = draft[key] ?? '';
  }
  if (workerApiKey.trim()) body.workerApiKey = workerApiKey.trim();
  return body;
}

/** The server's own gate (settings_routes.dart), mirrored so a credential-
 *  grade pick waits for the password instead of dying with a 401. */
function needsCredential(
  body: Record<string, unknown>,
  s: WorkerBackendFields,
): boolean {
  if (body.workerApiKey) return true;
  if ('workerRemoteApiUrl' in body &&
      String(body.workerRemoteApiUrl ?? '') !== (s.workerRemoteApiUrl ?? '')) {
    return true;
  }
  if ('workerKoboldModelPath' in body &&
      String(body.workerKoboldModelPath ?? '') !== (s.workerKoboldModelPath ?? '')) {
    return true;
  }
  if ('workerKoboldKcppsPath' in body &&
      String(body.workerKoboldKcppsPath ?? '') !== (s.workerKoboldKcppsPath ?? '')) {
    return true;
  }
  return false;
}

export function ChatWorkerLane({
  s,
  onSaved,
}: {
  /** The worker fields of the sheet's /api/settings snapshot. */
  s: WorkerBackendFields;
  /** Merge the POST response (a full snapshot) back into the sheet. */
  onSaved: (next: WorkerBackendFields) => void;
}) {
  const [draft, setDraft] = useState<Partial<WorkerBackendFields>>({});
  const [workerApiKey, setWorkerApiKey] = useState('');
  const [password, setPassword] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);
  const [totpCode, setTotpCode] = useState('');
  const [needsStepUp, setNeedsStepUp] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  // The exact payload a save failed with. The scheduler refuses to re-send
  // it on its own: every failed step-up counts against the login limiter's
  // small free allowance, so a wrong password must not become a retry loop.
  // A changed payload (new pick, edited password, typed TOTP code) posts
  // again; so does the Retry button, which clears this.
  const [failedKey, setFailedKey] = useState<string | null>(null);
  const alive = useRef(true);

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  // The card is fully controlled: server truth with the unsaved draft on top.
  const view: WorkerBackendFields = { ...s, ...draft };

  async function post(body: Record<string, unknown>, key: string) {
    if (saving) return;
    setSaving(true);
    setError('');
    try {
      const next = await api.post<WorkerBackendFields>('/api/settings', body);
      if (!alive.current) return;
      onSaved(next);
      // Drop only the keys this POST carried. A pick made while it was in
      // flight stays in the draft and saves next.
      setDraft((d) => {
        const rest: Partial<WorkerBackendFields> = { ...d };
        for (const key2 of WORKER_KEYS) {
          if (key2 in body && String(rest[key2] ?? '') === String(body[key2] ?? '')) {
            delete rest[key2];
          }
        }
        return rest;
      });
      if (body.workerApiKey) setWorkerApiKey('');
      setPassword('');
      setTotpCode('');
      setNeedsStepUp(false);
      setFailedKey(null);
    } catch (e) {
      if (!alive.current) return;
      setFailedKey(key);
      if (e instanceof ApiError && e.payload.totpRequired === true) {
        setTotpEnabled(true);
        setError('Enter your two-factor code to save the helper model.');
        return;
      }
      setError(e instanceof ApiError ? e.message : 'Could not save the helper model');
    } finally {
      if (alive.current) setSaving(false);
    }
  }

  function patch(p: Partial<WorkerBackendFields>) {
    setDraft((d) => ({ ...d, ...p }));
  }

  // One debounced scheduler is the only save path. Typing (password, custom
  // URL, API key) restarts the timer, so a burst of keystrokes produces one
  // POST with the final values — never a POST per keystroke, which would run
  // the login limiter down on partial passwords (auth_service's lockout).
  // When an in-flight save settles, this effect re-runs and a pick that
  // landed mid-flight posts next instead of dying with the sheet. A payload
  // that already failed never re-sends itself: only an edit (pick, password,
  // TOTP code) or the Retry button moves it again.
  useEffect(() => {
    if (saving) return;
    const body = bodyFor(draft, workerApiKey);
    if (Object.keys(body).length === 0) return;
    if (needsCredential(body, s)) {
      if (!password.trim()) {
        setNeedsStepUp(true);
        return;
      }
      attachStepUp(body, password, totpEnabled, totpCode);
    }
    const key = JSON.stringify(body);
    if (key === failedKey) return;
    const t = setTimeout(() => void post(body, key), 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draft, workerApiKey, password, totpCode, saving, failedKey, s]);

  return (
    <>
      <WorkerBackendCard
        compact
        s={view}
        workerApiKey={workerApiKey}
        onWorkerApiKey={setWorkerApiKey}
        onPatch={patch}
        savedRemoteApiUrl={s.remoteApiUrl ?? ''}
        chatApiKey=""
        currentPassword={password}
        totpCode={totpCode}
        totpEnabled={totpEnabled}
        onTotpRequired={() => setTotpEnabled(true)}
      />
      {needsStepUp && (
        <StepUpFields
          password={password}
          onPassword={setPassword}
          totpEnabled={totpEnabled}
          totpCode={totpCode}
          onTotp={setTotpCode}
          reason="The helper host and its model files are credential-grade settings. Confirm with your web login password."
        />
      )}
      {saving && <p className="muted small">Saving…</p>}
      {error && (
        <p className="error" role="alert">
          {error}{' '}
          <button
            type="button"
            className="link-btn"
            onClick={() => setFailedKey(null)}
          >
            Retry
          </button>
        </p>
      )}
    </>
  );
}
