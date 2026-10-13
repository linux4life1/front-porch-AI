// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useMemo, useState } from 'react';
import { api, ApiError } from '../../../api/client';
import {
  filterImageModels,
  imageModelListLabel,
  looksLikeLocalImageModel,
  sortImageModelsForPicker,
  type ImageRemoteModel,
} from '../imageRemote';

/** Change model on a Remote API: the host's image models, searchable. */
export function RemoteModelSheet(props: {
  current: string;
  onPick: (id: string) => void;
  onClose: () => void;
}) {
  const [models, setModels] = useState<ImageRemoteModel[] | null>(null);
  const [problem, setProblem] = useState('');
  const [filter, setFilter] = useState('');

  useEffect(() => {
    let live = true;
    api
      .get<{ models: ImageRemoteModel[] }>('/api/image/models')
      .then((r) => live && setModels(sortImageModelsForPicker(r.models ?? [])))
      .catch((e) => {
        if (!live) return;
        setModels([]);
        setProblem(e instanceof ApiError && e.message ? e.message : 'Could not list image models.');
      });
    return () => {
      live = false;
    };
  }, []);

  const shown = useMemo(() => filterImageModels(models ?? [], filter), [models, filter]);

  return (
    <div className="fp-sheet" role="dialog" aria-label="Select Image Model">
      <h3>Select Image Model</h3>
      <input
        aria-label="Filter models"
        placeholder="Filter models…"
        value={filter}
        onChange={(e) => setFilter(e.target.value)}
      />
      {models === null ? <p>Loading…</p> : null}
      {problem ? <p>{problem}</p> : null}
      {models !== null && !problem && shown.length === 0 ? <p>No matching models.</p> : null}
      <ul className="fp-remote-models">
        {shown.map((m) => (
          <li key={m.id}>
            <button
              type="button"
              aria-pressed={m.id === props.current}
              disabled={looksLikeLocalImageModel(m.id)}
              onClick={() => props.onPick(m.id)}
            >
              <span>{m.label || imageModelListLabel(m)}</span>
              <span className="fp-remote-id">{m.id}</span>
            </button>
          </li>
        ))}
      </ul>
      <button type="button" onClick={props.onClose}>
        Close
      </button>
    </div>
  );
}
