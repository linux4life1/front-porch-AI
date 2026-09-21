// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Image Studio Remote API: Nano / OpenRouter chips + searchable model list.
// Keys stay in Settings → Backend; chips only flip the Studio-scoped host.

import { useEffect, useMemo, useState } from 'react';
import { api, ApiError } from '../../api/client';
import {
  filterImageModels,
  imageModelListLabel,
  looksLikeLocalImageModel,
  sortImageModelsForPicker,
  type ImageRemoteHost,
  type ImageRemoteModel,
} from './imageRemote';

export function ImageRemoteFields({
  selectedHostId,
  hosts,
  modelId,
  hasApiKey,
  remoteApiUrl,
  onHost,
  onModel,
  onError,
}: {
  selectedHostId: string;
  hosts: ImageRemoteHost[];
  modelId: string;
  hasApiKey: boolean;
  remoteApiUrl: string;
  onHost: (id: string) => void;
  onModel: (id: string) => void;
  onError: (s: string) => void;
}) {
  const [models, setModels] = useState<ImageRemoteModel[]>([]);
  const [loading, setLoading] = useState(false);
  const [filter, setFilter] = useState('');
  const [open, setOpen] = useState(false);

  const load = () => {
    setLoading(true);
    api
      .get<{ models: ImageRemoteModel[] }>('/api/image/models')
      .then((r) => setModels(sortImageModelsForPicker(r.models ?? [])))
      .catch((e) => {
        setModels([]);
        onError(e instanceof ApiError ? e.message : 'Could not list image models');
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
    // Reload when the Studio host changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedHostId, remoteApiUrl]);

  const missing = hosts.filter((h) => !h.hasKey).map((h) => h.label);
  const hostName = (() => {
    try {
      return remoteApiUrl ? new URL(remoteApiUrl).host : '';
    } catch {
      return '';
    }
  })();
  const selected = models.find((m) => m.id === modelId);
  const filtered = useMemo(() => filterImageModels(models, filter), [models, filter]);

  return (
    <div className="img-remote">
      <div className="img-host-chips" role="group" aria-label="Image remote host">
        {hosts.map((h) => (
          <button
            key={h.id}
            type="button"
            data-testid={`image-remote-host-${h.id}`}
            className={`chip-toggle${selectedHostId === h.id ? ' on' : ''}`}
            disabled={!h.hasKey}
            title={h.hasKey ? h.label : `${h.label}: add a key in Settings → Backend`}
            onClick={() => onHost(h.id)}
          >
            {h.label}
          </button>
        ))}
      </div>
      {missing.length > 0 && (
        <p className="muted small">
          {missing.join(' / ')}: add a key in Settings → Backend.
        </p>
      )}
      {hasApiKey ? (
        <p className="muted small">
          Bills your Remote API account{hostName ? ` (${hostName})` : ''} per image.
        </p>
      ) : (
        <p className="muted small">
          No Remote API key configured for this host. Add it under Settings → Backend.
        </p>
      )}

      <label>
        Image model
        <div className="model-picker">
          <div className="model-picker-bar">
            <button
              type="button"
              className="model-picker-trigger"
              data-testid="image-remote-model-search"
              onClick={() => setOpen((o) => !o)}
              aria-haspopup="listbox"
              aria-expanded={open}
              disabled={loading || models.length === 0}
            >
              <span className={selected || modelId ? 'mp-value' : 'mp-value muted'}>
                {selected
                  ? selected.label || imageModelListLabel(selected)
                  : modelId || (loading ? 'Loading…' : 'Search models…')}
              </span>
              <span className="mp-caret" aria-hidden>▾</span>
            </button>
            <button
              type="button"
              className="ghost mp-refresh"
              onClick={() => load()}
              disabled={loading}
              aria-label="Refresh image models"
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
              {filtered.length === 0 ? (
                <div className="mp-state muted">No matching models.</div>
              ) : (
                <ul className="mp-list">
                  {filtered.map((m) => (
                    <li key={m.id}>
                      <button
                        type="button"
                        role="option"
                        className={`mp-option${m.id === modelId ? ' selected' : ''}`}
                        onClick={() => {
                          if (looksLikeLocalImageModel(m.id)) return;
                          onModel(m.id);
                          setOpen(false);
                          setFilter('');
                        }}
                      >
                        <span className="mp-name">{m.label || imageModelListLabel(m)}</span>
                        <span className="mp-meta muted">{m.id}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </div>
      </label>
    </div>
  );
}
