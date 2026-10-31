// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Backups & Restore, matching the desktop Backups page: automatic snapshots
// (library + settings) and full backups (library, settings and the user's
// own files). Every restore from here waits for the desktop's next launch.

import { useEffect, useState } from 'react';
import { api, ApiError, parseApiErrorBody } from '../api/client';
import { attachStepUp, StepUpFields } from '../components/StepUpFields';

export interface Snapshot {
  id: string;
  created: number;
  size: number;
  hasSettings: boolean;
}

export interface BackupState {
  nightly: boolean;
  maxSnapshots: number;
  dailyDays: number;
  snapshots: Snapshot[];
  pending: { kind: 'full' | 'snapshot' | 'settings'; created: number; staged: number } | null;
}

export function restoreScope(kind: 'full' | 'snapshot' | 'settings'): string {
  if (kind === 'full') return 'library, settings and files';
  if (kind === 'snapshot') return 'library and settings';
  return 'settings';
}

function when(ms: number): string {
  return new Date(ms).toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  });
}

function megabytes(bytes: number): string {
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const FINISH = 'It finishes the next time Front Porch AI is opened on your computer.';

export function BackupsPage() {
  const [state, setState] = useState<BackupState | null>(null);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState('');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);
  const [restoring, setRestoring] = useState<Snapshot | null>(null);
  const [withSettings, setWithSettings] = useState(true);
  const [includeSecrets, setIncludeSecrets] = useState(false);
  const [file, setFile] = useState<File | null>(null);

  const load = () =>
    api
      .get<BackupState>('/api/backups')
      .then(setState)
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Could not load backups'));

  useEffect(() => {
    void load();
    api
      .get<{ totpEnabled?: boolean }>('/api/auth/state')
      .then((s) => setTotpEnabled(!!s.totpEnabled))
      .catch(() => {});
  }, []);

  const act = async (key: string, fn: () => Promise<void>) => {
    setBusy(key);
    setError('');
    setNote('');
    try {
      await fn();
    } catch (e) {
      if (e instanceof ApiError && e.payload.totpRequired === true) setTotpEnabled(true);
      setError(e instanceof ApiError ? e.message : 'That did not work. Try again.');
    } finally {
      setBusy('');
    }
  };

  const stepUp = (reason: string) => (
    <StepUpFields
      password={password}
      onPassword={setPassword}
      totpEnabled={totpEnabled}
      totpCode={totpCode}
      onTotp={setTotpCode}
      reason={reason}
    />
  );

  const createSnapshot = () =>
    act('create', async () => {
      setState(await api.post<BackupState>('/api/backups'));
      setNote('Backup created.');
    });

  const deleteSnapshot = (s: Snapshot) => {
    if (!window.confirm(`Delete the backup from ${when(s.created)}? This cannot be undone.`)) return;
    void act(`del-${s.id}`, async () => {
      setState(await api.del<BackupState>(`/api/backups/${encodeURIComponent(s.id)}`));
    });
  };

  const restoreSnapshot = (s: Snapshot) =>
    act(`restore-${s.id}`, async () => {
      const body: Record<string, unknown> = { withSettings: s.hasSettings && withSettings };
      attachStepUp(body, password, totpEnabled, totpCode);
      setState(await api.post<BackupState>(`/api/backups/${encodeURIComponent(s.id)}/restore`, body));
      setRestoring(null);
      setPassword('');
      setTotpCode('');
      setNote(`The backup from ${when(s.created)} is ready to restore. ${FINISH}`);
    });

  const cancelPending = () =>
    act('cancel', async () => {
      setState(await api.del<BackupState>('/api/backups/pending'));
      setNote('The restore was cancelled.');
    });

  const downloadFull = () =>
    act('full', async () => {
      const body: Record<string, unknown> = { includeSecrets };
      if (includeSecrets) attachStepUp(body, password, totpEnabled, totpCode);
      const r = await api.post<{ token: string; fileName: string; size: number }>(
        '/api/backups/full',
        body,
      );
      // A plain link, so the browser streams a large file to disk.
      const a = document.createElement('a');
      a.href = `/api/backups/full/${r.token}`;
      a.download = r.fileName;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setNote(`Downloading ${r.fileName} (${megabytes(r.size)}).`);
    });

  const restoreFull = () =>
    act('upload', async () => {
      if (!file) return;
      const headers: Record<string, string> = {
        'Content-Type': 'application/octet-stream',
        'X-Current-Password': password,
      };
      if (totpEnabled && totpCode.trim()) headers['X-Totp-Code'] = totpCode.trim();
      const res = await fetch('/api/backups/full/restore', {
        method: 'POST',
        credentials: 'include',
        headers,
        body: file,
      });
      const text = await res.text();
      if (!res.ok) throw parseApiErrorBody(text, res.status);
      const next = JSON.parse(text) as BackupState & { restored: { created: number } };
      setState(next);
      setFile(null);
      setPassword('');
      setTotpCode('');
      setNote(`The backup from ${when(next.restored.created)} is ready to restore. ${FINISH}`);
    });

  return (
    <div className="page backups-page">
      <h2>Backups &amp; restore</h2>
      {error && <p className="error">{error}</p>}
      {note && <p className="muted">{note}</p>}

      {state?.pending && (
        <section className="card" data-testid="pending-restore">
          <p>
            A restore is waiting. Your {restoreScope(state.pending.kind)} go back to the backup from{' '}
            {when(state.pending.created)} the next time Front Porch AI is opened on your computer.
          </p>
          <button onClick={cancelPending} disabled={busy === 'cancel'}>
            Cancel restore
          </button>
        </section>
      )}

      <section className="card">
        <h3>Automatic snapshots</h3>
        <p className="muted small">
          A snapshot of your library and settings is taken every 30 minutes. The newest{' '}
          {state?.maxSnapshots ?? 10} are always kept, plus one per day for the last{' '}
          {state?.dailyDays ?? 7} days. Snapshots stay on your computer.
        </p>
        <button onClick={createSnapshot} disabled={busy === 'create'}>
          Create backup now
        </button>
        {state && state.snapshots.length === 0 && (
          <p className="muted">No backups yet. One is created automatically every 30 minutes.</p>
        )}
        <ul className="backup-list">
          {state?.snapshots.map((s) => (
            <li key={s.id}>
              <div className="backup-row">
                <span>
                  {when(s.created)}
                  <span className="muted small">
                    {' '}
                    · {megabytes(s.size)} · {s.hasSettings ? 'library and settings' : 'library only'}
                  </span>
                </span>
                <span className="backup-actions">
                  <button onClick={() => setRestoring(restoring?.id === s.id ? null : s)}>Restore</button>
                  <button onClick={() => deleteSnapshot(s)} aria-label="Delete backup" disabled={busy === `del-${s.id}`}>
                    Delete
                  </button>
                </span>
              </div>
              {restoring?.id === s.id && (
                <div className="backup-confirm">
                  <p className="muted small">
                    Your library goes back to this snapshot. Anything changed after it was taken is lost.{' '}
                    {FINISH}
                  </p>
                  {s.hasSettings && (
                    <label className="checkbox">
                      <input
                        type="checkbox"
                        checked={withSettings}
                        onChange={(e) => setWithSettings(e.target.checked)}
                      />{' '}
                      Also restore settings
                    </label>
                  )}
                  {stepUp('Restoring replaces your library. Confirm your web login password.')}
                  <button
                    onClick={() => void restoreSnapshot(s)}
                    disabled={!password || busy === `restore-${s.id}`}
                  >
                    Restore this backup
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      </section>

      <section className="card">
        <h3>Full backup</h3>
        <p className="muted small">
          One file with your whole library, every setting (saved prompts, presets, themes, voices) and your own files:
          character pictures, galleries, worlds, backgrounds, imported voices and stories. Downloaded models and engines
          are left out; the app gets them again.
        </p>
        <label className="checkbox">
          <input
            type="checkbox"
            checked={includeSecrets}
            onChange={(e) => setIncludeSecrets(e.target.checked)}
          />{' '}
          Include API keys and sign-ins
        </label>
        <p className="muted small">
          Anyone with the file can use them. Leave this off for a backup you share or store online.
        </p>
        {includeSecrets && stepUp('A backup with API keys in it is credential-grade. Confirm your web login password.')}
        <button onClick={downloadFull} disabled={busy === 'full' || (includeSecrets && !password)}>
          {busy === 'full' ? 'Making the backup…' : 'Download full backup'}
        </button>

        <h4>Restore from a file</h4>
        <input
          type="file"
          accept=".fpbackup"
          aria-label="Backup file"
          onChange={(e) => setFile(e.target.files?.[0] ?? null)}
        />
        {file && (
          <div className="backup-confirm">
            <p className="muted small">
              Your library, settings and files are replaced by the ones in {file.name}. A snapshot of everything as it
              is now is taken first. {FINISH}
            </p>
            {!includeSecrets && stepUp('Restoring replaces your library. Confirm your web login password.')}
            <button onClick={restoreFull} disabled={!password || busy === 'upload'}>
              {busy === 'upload' ? 'Uploading…' : 'Restore this file'}
            </button>
          </div>
        )}
      </section>
    </div>
  );
}
