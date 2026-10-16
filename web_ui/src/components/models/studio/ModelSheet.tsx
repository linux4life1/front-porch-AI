// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { fetchCatalog, fetchLocalCatalog } from './deskApi';
import type { Mode } from './types';

/**
 * Change model, or Change one of the files the graph also loads. Files that
 * look wrong for the model are listed last and marked; nothing is hidden,
 * because a name is only a guess.
 */
export function ModelSheet(props: {
  mode: Mode;
  backend: string;
  /** The slot being changed (`%MODEL_CLIP%`...), or none for the model. */
  token?: string;
  primary: string;
  onPick: (file: string) => void;
  onClose: () => void;
}) {
  const [query, setQuery] = useState('');
  const [files, setFiles] = useState<string[]>([]);
  const [unfit, setUnfit] = useState<string[]>([]);
  const [failed, setFailed] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  // Bumped by Refresh list to read the connected app's files again.
  const [reads, setReads] = useState(0);
  const listed = props.backend === 'drawthings' || props.backend === 'comfyui';

  useEffect(() => {
    let live = true;
    setFailed(false);
    setRefreshing(true);
    // A read that comes back empty (the app is not answering) leaves the files
    // already listed, so a refresh never takes files away.
    const done = (list: string[], odd: string[] = []) => {
      if (!live || list.length === 0) return;
      setFiles(list);
      setUnfit(odd);
    };
    const settle = () => {
      if (live) setRefreshing(false);
    };
    if (props.backend === 'drawthings') {
      void fetchLocalCatalog('')
        .then((cat) => done(cat.models ?? []))
        .catch(() => live && setFailed(true))
        .finally(settle);
    } else if (props.backend === 'comfyui') {
      void fetchCatalog(props.mode, { token: props.token })
        .then((cat) =>
          props.token
            ? done(cat.slotFiles?.files ?? [], cat.slotFiles?.unfit ?? [])
            : done(cat.deskDiscovery ?? []),
        )
        .catch(() => live && setFailed(true))
        .finally(settle);
    } else {
      setRefreshing(false);
    }
    return () => {
      live = false;
    };
    // Read when the sheet opens and on each Refresh list.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reads]);

  const q = query.trim().toLowerCase();
  const shown = files.filter((name) => !q || name.toLowerCase().includes(q));
  return (
    <div className="fp-sheet" role="dialog" aria-label="Change model">
      <button type="button" onClick={props.onClose}>Close</button>
      <h2>
        {props.token
          ? `Change ${props.token.includes('VAE') ? 'VAE' : 'text encoder'}`
          : props.mode === 'edit' ? 'Change model — Edit' : 'Change model — Create'}
      </h2>
      {listed ? (
        <button type="button" disabled={refreshing} onClick={() => setReads((n) => n + 1)}>
          {refreshing ? 'Loading...' : 'Refresh models'}
        </button>
      ) : null}
      <input
        aria-label="Search files"
        placeholder="Search families or files"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {failed ? <p>The list could not be read.</p> : null}
      <ul>
        {shown.map((name) => (
          <li key={name}>
            <button type="button" onClick={() => props.onPick(name)}>
              {unfit.includes(name) ? `${name} (may not fit ${props.primary || 'this model'})` : name}
            </button>
          </li>
        ))}
      </ul>
      {q ? (
        <button type="button" onClick={() => props.onPick(query.trim())}>
          {`Use ${query.trim()}`}
        </button>
      ) : null}
    </div>
  );
}
