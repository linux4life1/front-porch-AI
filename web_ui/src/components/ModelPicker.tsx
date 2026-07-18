// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Strict fetched model dropdown for remote / OpenAI-compatible backends. The
// user never types a raw model id — the list is pulled from the provider's
// /models endpoint (POST /api/backend/remote-models, which reuses
// OpenRouterService.fetchAvailableModels). Selection is from the fetched list
// only; on failure the sole path forward is Retry, mirroring the desktop app.

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';

interface RemoteModel {
  id: string;
  name: string;
  pricing: string;
  free: boolean;
}

export function ModelPicker({
  apiUrl,
  apiKey,
  value,
  onChange,
}: {
  apiUrl: string;
  /** The unsaved API key from the form (may be ''); when blank the server falls
   *  back to the stored key, so an existing setup still lists models. */
  apiKey: string;
  value: string;
  onChange: (id: string) => void;
}) {
  const [models, setModels] = useState<RemoteModel[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [open, setOpen] = useState(false);
  const [filter, setFilter] = useState('');
  const boxRef = useRef<HTMLDivElement>(null);

  const fetchModels = async () => {
    setLoading(true);
    setError('');
    try {
      const body: Record<string, unknown> = {};
      if (apiUrl.trim()) body.apiUrl = apiUrl.trim();
      if (apiKey.trim()) body.apiKey = apiKey.trim();
      const r = await api.post<{ models: RemoteModel[] }>('/api/backend/remote-models', body);
      const list = r.models ?? [];
      setModels(list);
      if (list.length === 0) {
        setError('No models returned. Check the API URL and key, then retry.');
      }
    } catch (e) {
      setModels([]);
      setError(e instanceof ApiError ? e.message : 'Could not reach the provider.');
    } finally {
      setLoading(false);
    }
  };

  // (Re)fetch on mount and whenever the provider URL changes, debounced so
  // typing a custom URL doesn't fire a request per keystroke. A blank URL skips.
  useEffect(() => {
    const t = setTimeout(() => void fetchModels(), 400);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [apiUrl]);

  // Close the dropdown when clicking outside it.
  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, [open]);

  const term = filter.trim().toLowerCase();
  const filtered = term
    ? models.filter((m) => `${m.id} ${m.name}`.toLowerCase().includes(term))
    : models;

  return (
    <div className="model-picker" ref={boxRef}>
      <div className="model-picker-bar">
        <button
          type="button"
          className="model-picker-trigger"
          onClick={() => setOpen((o) => !o)}
          aria-haspopup="listbox"
          aria-expanded={open}
        >
          <span className={value ? 'mp-value' : 'mp-value muted'}>{value || 'Select a model…'}</span>
          <span className="mp-caret" aria-hidden>▾</span>
        </button>
        <button
          type="button"
          className="ghost mp-refresh"
          onClick={() => void fetchModels()}
          disabled={loading}
          title="Refresh model list"
          aria-label="Refresh model list"
        >
          {loading ? '…' : '⟳'}
        </button>
      </div>

      {open && (
        <div className="model-picker-menu" role="listbox">
          <input
            className="mp-filter"
            placeholder="Filter models…"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            autoFocus
          />
          {loading ? (
            <div className="mp-state"><div className="spinner" /></div>
          ) : error ? (
            <div className="mp-state mp-error">
              <p>{error}</p>
              <button type="button" className="ghost" onClick={() => void fetchModels()}>Retry</button>
            </div>
          ) : filtered.length === 0 ? (
            <div className="mp-state muted">No matching models.</div>
          ) : (
            <ul className="mp-list">
              {filtered.map((m) => (
                <li key={m.id}>
                  <button
                    type="button"
                    role="option"
                    aria-selected={m.id === value}
                    className={`mp-option${m.id === value ? ' selected' : ''}`}
                    onClick={() => { onChange(m.id); setOpen(false); setFilter(''); }}
                  >
                    <span className="mp-name">{m.name || m.id}</span>
                    <span className="mp-meta muted">
                      {m.id}
                      {m.pricing ? ` · ${m.free ? 'Free' : m.pricing}` : ''}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {/* Persistent inline error when closed, so a failed fetch is visible without
          opening the menu. Retry re-runs the fetch. */}
      {!open && error && (
        <p className="mp-inline-error">
          {error}{' '}
          <button type="button" className="link-btn" onClick={() => void fetchModels()}>Retry</button>
        </p>
      )}
    </div>
  );
}
