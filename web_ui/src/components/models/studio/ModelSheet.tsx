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

  useEffect(() => {
    let live = true;
    const done = (list: string[], odd: string[] = []) => {
      if (!live) return;
      setFiles(list);
      setUnfit(odd);
    };
    if (props.backend === 'drawthings') {
      void fetchLocalCatalog('')
        .then((cat) => done(cat.models ?? []))
        .catch(() => live && setFailed(true));
    } else if (props.backend === 'comfyui') {
      void fetchCatalog(props.mode, { token: props.token })
        .then((cat) =>
          props.token
            ? done(cat.slotFiles?.files ?? [], cat.slotFiles?.unfit ?? [])
            : done(cat.deskDiscovery ?? []),
        )
        .catch(() => live && setFailed(true));
    }
    return () => {
      live = false;
    };
    // Read once when the sheet opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
