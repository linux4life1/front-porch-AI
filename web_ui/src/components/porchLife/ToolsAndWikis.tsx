// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';
import type { ExpandSignal } from './FeatureGroup';

const AWAY_OPTIONS: { value: number; label: string }[] = [
  { value: 12, label: '12 hours' },
  { value: 24, label: 'a day' },
  { value: 72, label: '3 days' },
  { value: 168, label: 'a week' },
];

/** The "away for at least" dropdown riding the absence-acknowledgement row.
 *  Values are clamped to a known option so a hand-edited preference can't
 *  assert the dropdown (carried over from the desktop widget). */
export function AwayThreshold({
  value,
  onChange,
}: {
  value: number;
  onChange: (v: number) => void;
}) {
  const known = AWAY_OPTIONS.some((o) => o.value === value) ? value : 24;
  return (
    <label className="pl-away row-label">
      <span>Away for at least</span>
      <select value={known} onChange={(e) => onChange(Number(e.target.value))}>
        {AWAY_OPTIONS.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

function wikiHostLabel(url: string): string {
  try {
    const u = new URL(url.includes('://') ? url : `https://${url}`);
    const path = u.pathname.replace(/\/$/, '');
    if (!path) return u.host || url;
    return `${u.host}${path}`;
  } catch {
    return url;
  }
}

export function WikiUrlList({
  saved,
  onSaved,
}: {
  saved: string[];
  onSaved: (urls: string[]) => void;
}) {
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const reload = async () => {
    const r = await api.get<{ realism?: { wikiSavedUrls?: string[] } }>(
      '/api/settings',
    );
    onSaved(r.realism?.wikiSavedUrls ?? []);
  };
  const add = async () => {
    const next = draft.trim();
    if (busy || !next) return;
    setBusy(true);
    setError('');
    try {
      await api.post('/api/settings', { realism: { wikiSavedUrlAdd: next } });
      const r = await api.get<{ realism?: { wikiSavedUrls?: string[] } }>(
        '/api/settings',
      );
      const urls = r.realism?.wikiSavedUrls ?? [];
      onSaved(urls);
      const host = wikiHostLabel(next);
      if (!urls.some((u) => wikiHostLabel(u) === host)) {
        setError('That is not a MediaWiki / Fandom URL.');
      } else {
        setDraft('');
      }
    } catch {
      setError('That is not a MediaWiki / Fandom URL.');
    } finally {
      setBusy(false);
    }
  };
  const remove = async (url: string) => {
    if (busy) return;
    setBusy(true);
    try {
      await api.post('/api/settings', { realism: { wikiSavedUrlRemove: url } });
      await reload();
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="pl-row pl-search-key" data-testid="wiki-url-field">
      <div className="pl-row-label-line">
        <span className="pl-label">Custom Wikis</span>
      </div>
      <p className="pl-subtitle">
        MediaWiki or Fandom sites for focused lore lookups.
      </p>
      <label className="pl-wiki-label">
        Wiki URL
        <input
          type="url"
          autoComplete="off"
          placeholder="https://bleach.fandom.com/"
          value={draft}
          disabled={busy}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && void add()}
        />
      </label>
      <p className="muted small">
        Looks up this wiki only (MediaWiki / Fandom). Not Google.
      </p>
      <div className="tool-row">
        <button
          className="primary"
          disabled={busy || !draft.trim()}
          onClick={() => void add()}
        >
          {busy ? 'Saving…' : 'Save wiki'}
        </button>
      </div>
      {error && <p className="error">{error}</p>}
      <details className="pl-wiki-acc" open data-testid="wiki-url-list">
        <summary>Saved wikis{saved.length ? ` (${saved.length})` : ''}</summary>
        {saved.length === 0 ? (
          <p className="muted small">None saved yet.</p>
        ) : (
          <ul className="pl-wiki-list">
            {saved.map((url) => (
              <li key={url} className="pl-wiki-row">
                <span>{wikiHostLabel(url)}</span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void remove(url)}
                >
                  Remove
                </button>
              </li>
            ))}
          </ul>
        )}
      </details>
    </div>
  );
}

export function SearchKeyRow({
  alreadySet,
  onStoredChange,
}: {
  alreadySet: boolean;
  onStoredChange: (stored: boolean) => void;
}) {
  const [value, setValue] = useState('');
  const [saved, setSaved] = useState(alreadySet);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  useEffect(() => setSaved(alreadySet), [alreadySet]);

  const save = async (clear = false) => {
    const next = clear ? '' : value.trim();
    if (busy || (!clear && !next)) return;
    setBusy(true);
    setError('');
    setMessage('');
    try {
      await api.post('/api/settings', { realism: { searchApiKey: next } });
      setValue('');
      setSaved(!clear);
      onStoredChange(!clear);
      setMessage(
        clear
          ? 'Key removed — searches use Wikipedia.'
          : 'Tavily key saved securely.',
      );
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not save that key');
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="pl-search-key">
      <label>
        {saved ? 'Tavily API key (saved securely)' : 'Tavily API key'}
        <input
          type="password"
          autoComplete="off"
          placeholder={saved ? 'Paste a replacement key' : 'Paste key'}
          value={value}
          disabled={busy}
          onChange={(e) => setValue(e.target.value)}
        />
      </label>
      <div className="tool-row">
        <button
          className="primary"
          disabled={busy || !value.trim()}
          onClick={() => void save()}
        >
          {busy ? 'Saving…' : 'Save key'}
        </button>
        {saved && (
          <button disabled={busy} onClick={() => void save(true)}>
            Remove key
          </button>
        )}
      </div>
      {message && <span className="muted small">{message}</span>}
      {error && <span className="error">{error}</span>}
    </div>
  );
}

export function FolderNoteRow({
  icon,
  title,
  subtitle,
  testId,
  body,
  expandDetailsSignal,
}: {
  icon: string;
  title: string;
  subtitle: string;
  testId: string;
  body: string;
  expandDetailsSignal?: ExpandSignal;
}) {
  const [detailsExpanded, setDetailsExpanded] = useState(
    expandDetailsSignal ? expandDetailsSignal.expanded : true,
  );

  useEffect(() => {
    if (expandDetailsSignal && expandDetailsSignal.version > 0) {
      setDetailsExpanded(expandDetailsSignal.expanded);
    }
  }, [expandDetailsSignal]);

  return (
    <div className="pl-row" data-testid={testId}>
      <div className="pl-row-main">
        <span className="pl-row-icon" aria-hidden="true">
          {icon}
        </span>
        <div className="pl-row-body">
          <button
            type="button"
            className="pl-row-toggle"
            aria-expanded={detailsExpanded}
            title={
              detailsExpanded
                ? 'Click to hide details'
                : 'Click to show details'
            }
            onClick={() => setDetailsExpanded((v) => !v)}
          >
            <span className="pl-label">{title}</span>
            <span className="pl-subtitle">{subtitle}</span>
          </button>
        </div>
      </div>
      {detailsExpanded && (
        <div className="pl-details-wrap">
          <p className="pl-blurb">{body}</p>
        </div>
      )}
    </div>
  );
}
