// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { StepUpFields } from '../../StepUpFields';
import { civitaiBaseGroups, filterCivitaiBases, visibleCivitaiBase } from '../civitaiBases';
import {
  cancelJob,
  civitaiNote,
  installedNames,
  jobStatus,
  keySaved,
  saveKey,
  searchCivitai,
  startDownload,
  type CivitaiRow,
} from './civitaiApi';
import type { CivitaiJob } from './types';

const POLL_MS = 1000;

/** The computer's words for a download that failed, unless it sent a raw page. */
function failureNote(job: CivitaiJob): string {
  const message = job.error?.trim() ?? '';
  return message && !message.startsWith('<') ? message : 'CivitAI download failed.';
}

/**
 * Get a model or a LoRA from CivitAI. Search and the saved key go through the
 * computer; the download runs there while this shows how far it is, and can
 * stop it. Adult results are asked for only when the app allows them.
 */
export function CivitaiSheet(props: {
  lora: boolean;
  backend: string;
  adultAllowed: boolean;
  totpEnabled: boolean;
  /** Called when a download finished: pick the file into the desk. */
  onInstalled: (filename: string, lora: boolean) => Promise<string>;
  onClose: () => void;
  /** How often the computer is asked how far a download is; for tests. */
  pollMs?: number;
}) {
  const { lora } = props;
  const title = lora ? 'Get a LoRA from CivitAI' : 'Get a model from CivitAI';
  const [query, setQuery] = useState('');
  const [adult, setAdult] = useState(false);
  const [base, setBase] = useState('');
  const [baseQuery, setBaseQuery] = useState('');
  const [installedOnly, setInstalledOnly] = useState(false);
  const [installed, setInstalled] = useState<{ bases: string[]; models: string[]; loras: string[] } | null>(null);
  const [rows, setRows] = useState<CivitaiRow[]>([]);
  const [detail, setDetail] = useState<CivitaiRow | null>(null);
  const [saved, setSaved] = useState(false);
  const [token, setToken] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [job, setJob] = useState<CivitaiJob | null>(null);
  const [note, setNote] = useState('');
  const live = useRef(true);
  const running = useRef<string | null>(null);

  useEffect(() => {
    live.current = true;
    void keySaved().then((s) => live.current && setSaved(s)).catch(() => live.current && setNote('Could not read the saved CivitAI key.'));
    void installedNames(props.backend)
      .then((b) => live.current && setInstalled({ bases: b.bases ?? [], models: b.models ?? [], loras: b.loras ?? [] }))
      .catch(() => live.current && setInstalled({ bases: [], models: [], loras: [] }));
    return () => {
      live.current = false;
    };
  }, [props.backend]);

  const have = (name: string) =>
    (lora ? installed?.loras : installed?.models)?.some((n) => n.toLowerCase() === name.toLowerCase()) ?? false;

  const shownBases = filterCivitaiBases(civitaiBaseGroups, baseQuery, installedOnly ? installed?.bases ?? [] : null);
  const baseSent = visibleCivitaiBase(base, shownBases);

  const search = () => {
    const q = query.trim();
    if (!q) return;
    setNote('');
    setDetail(null);
    void searchCivitai({ query: q, lora, adult: adult && props.adultAllowed, base: baseSent })
      .then(({ rows: found, needsCredential }) => {
        if (!live.current) return;
        if (needsCredential) {
          setNote('Paste an API key to search adult models.');
          setRows([]);
          return;
        }
        setRows(found);
        if (found.length === 0) setNote('CivitAI returned no models for that search.');
      })
      .catch((e: unknown) => {
        if (!live.current) return;
        setRows([]);
        setNote(civitaiNote(e, 'CivitAI search failed.'));
      });
  };

  const saveTheKey = () => {
    const t = token.trim();
    if (!t) return;
    void saveKey(t, password, props.totpEnabled ? totp : undefined)
      .then(() => {
        if (!live.current) return;
        setSaved(true);
        setToken('');
        setPassword('');
        setTotp('');
        setNote('API key saved.');
      })
      .catch((e: unknown) => live.current && setNote(civitaiNote(e, 'Could not save the API key.')));
  };

  const finish = (row: CivitaiRow) => {
    void props.onInstalled(row.filename, lora).then((message) => {
      if (live.current) setNote(message);
    });
  };

  const watch = async (id: string, row: CivitaiRow) => {
    running.current = id;
    for (;;) {
      await new Promise((resolve) => setTimeout(resolve, props.pollMs ?? POLL_MS));
      if (!live.current || running.current !== id) return;
      let next: CivitaiJob;
      try {
        next = await jobStatus(id);
      } catch (e) {
        if (!live.current) return;
        running.current = null;
        setJob(null);
        setNote(civitaiNote(e, 'CivitAI download failed.'));
        return;
      }
      if (!live.current || running.current !== id) return;
      setJob(next);
      if (next.state === 'running') continue;
      running.current = null;
      setJob(null);
      if (next.state === 'done') finish(row);
      else if (next.state === 'cancelled') setNote('The download was cancelled.');
      else setNote(failureNote(next));
      return;
    }
  };

  const download = (row: CivitaiRow) => {
    if (running.current) return;
    setNote('Downloading on your computer…');
    running.current = 'starting';
    void startDownload({
      versionId: row.versionId,
      backend: props.backend,
      adult: adult && props.adultAllowed,
      filename: row.filename,
      lora,
    })
      .then((started) => {
        if (!live.current) return;
        setJob(started);
        void watch(started.jobId, row);
      })
      .catch((e: unknown) => {
        running.current = null;
        if (live.current) setNote(civitaiNote(e, 'CivitAI download failed.'));
      });
  };

  const close = () => {
    const id = running.current;
    if (id && id !== 'starting') void cancelJob(id).catch(() => {});
    running.current = null;
    props.onClose();
  };

  const pick = (row: CivitaiRow) => (have(row.filename) ? finish(row) : download(row));
  const label = (row: CivitaiRow) => (have(row.filename) ? 'Installed' : row.filename);
  const percent = job ? Math.max(0, Math.min(100, Math.round(job.percent))) : 0;
  // Rows fetched with adult results on go away when it is turned off.
  const results = rows.filter((row) => adult || !row.adult);

  return (
    <div className="fp-civitai-page" role="dialog" aria-label={title}>
      <button type="button" onClick={close}>Close</button>
      <h2>{detail?.name || title}</h2>
      {props.adultAllowed ? (
        <label>
          <input
            type="checkbox"
            checked={adult}
            onChange={(e) => {
              setAdult(e.target.checked);
              setRows([]);
              setDetail(null);
            }}
          />
          Include adult models from civitai.red
        </label>
      ) : null}
      {saved ? (
        <p>
          API key saved. Search and adult results on civitai.red use this key.
          <button type="button" onClick={() => setSaved(false)}>Replace</button>
        </p>
      ) : (
        <div>
          <label>
            API key
            <input type="password" autoComplete="off" value={token} onChange={(e) => setToken(e.target.value)} />
          </label>
          {token.trim() ? (
            <>
              <StepUpFields
                password={password}
                onPassword={setPassword}
                totpEnabled={props.totpEnabled}
                totpCode={totp}
                onTotp={setTotp}
                reason="Saving the CivitAI key — confirm your web login password."
              />
              <button type="button" disabled={!password} onClick={saveTheKey}>Save key</button>
            </>
          ) : null}
        </div>
      )}
      <label>
        Filter bases
        <input
          aria-label="Filter bases"
          placeholder="Qwen, Flux, SDXL"
          value={baseQuery}
          onChange={(e) => setBaseQuery(e.target.value)}
        />
      </label>
      <label>
        <input type="checkbox" checked={installedOnly} onChange={(e) => setInstalledOnly(e.target.checked)} />
        Only installed models
      </label>
      {installedOnly && !installed ? <p>Looking through the models folder…</p> : null}
      <label>
        Base model
        <select aria-label="Base model" value={baseSent} onChange={(e) => setBase(e.target.value)}>
          <option value="">Any base</option>
          {shownBases.map((group) => (
            <optgroup key={group.title} label={group.title}>
              {group.choices.map((choice) => (
                <option key={choice.api} value={choice.api}>{choice.label}</option>
              ))}
            </optgroup>
          ))}
        </select>
      </label>
      {installedOnly && installed && shownBases.length === 0 ? <p>No installed model matches a CivitAI base.</p> : null}
      <input
        aria-label="Search"
        placeholder={lora ? 'Clothes' : 'Search CivitAI'}
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && search()}
      />
      <button type="button" onClick={search}>Search</button>
      {job ? (
        <div>
          <progress aria-label="Download progress" max={100} value={percent} />
          <span>{`${percent}%`}</span>
          <button type="button" onClick={() => void cancelJob(job.jobId).catch(() => {})}>Cancel download</button>
        </div>
      ) : null}
      {detail ? (
        <div>
          {detail.preview ? (
            <img alt="" src={detail.preview} referrerPolicy="no-referrer" style={{ width: '100%', objectFit: 'contain', maxHeight: '70vh' }} />
          ) : null}
          <p>{(detail.downloads ?? 0).toLocaleString()} downloads</p>
          <p>{detail.description || 'CivitAI did not send a description.'}</p>
          <button type="button" onClick={() => setDetail(null)}>Back</button>
          <button type="button" onClick={() => pick(detail)}>{have(detail.filename) ? 'Installed' : 'Download'}</button>
        </div>
      ) : (
        results.map((row) => (
          <div key={`${row.versionId}:${row.filename}`} style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '8px 0' }}>
            <button type="button" onClick={() => setDetail(row)} style={{ display: 'flex', gap: 8, textAlign: 'left' }}>
              {row.preview ? <img alt="" src={row.preview} width={88} height={88} referrerPolicy="no-referrer" style={{ objectFit: 'cover' }} /> : null}
              <span>
                <strong>{row.name || row.filename}</strong>
                <span>{(row.downloads ?? 0).toLocaleString()} downloads</span>
              </span>
            </button>
            <button type="button" onClick={() => pick(row)}>{label(row)}</button>
          </div>
        ))
      )}
      {note ? <p>{note}</p> : null}
    </div>
  );
}
