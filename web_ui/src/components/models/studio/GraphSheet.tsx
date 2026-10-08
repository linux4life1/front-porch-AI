// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { ApiError } from '../../../api/client';
import { StepUpFields } from '../../StepUpFields';
import { fetchCatalog, MAX_GRAPH_BYTES, uploadGraph } from './deskApi';
import { graphMatches } from './deskRules';
import type { GraphRow, GraphUpload, Mode } from './types';

/**
 * Change graph. The lists come from one read of the Comfy install. A graph
 * file is sent to the server, which checks it and stores it after the web
 * password; a graph meant for the other mode waits for the person to say which.
 */
export function GraphSheet(props: {
  mode: Mode;
  backend: string;
  totpEnabled: boolean;
  onPick: (id: string, mode: Mode) => void;
  onStored: (result: GraphUpload) => void;
  onClose: () => void;
}) {
  const { mode } = props;
  const [create, setCreate] = useState<GraphRow[]>([]);
  const [edit, setEdit] = useState<GraphRow[]>([]);
  const [note, setNote] = useState('Reading this Comfy’s templates…');
  const [query, setQuery] = useState('');
  const [file, setFile] = useState<{ name: string; bytes: Uint8Array } | null>(null);
  const [asks, setAsks] = useState<GraphUpload['stance'] | null>(null);
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [error, setError] = useState('');
  const chooser = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let live = true;
    void fetchCatalog(mode)
      .then((cat) => {
        if (!live) return;
        setCreate(cat.graphs ?? []);
        setEdit(cat.editGraphs ?? []);
        setNote(
          props.backend === 'comfyui'
            ? 'The first group is built into Front Porch. Saved workflows are only listed for the mode their graph matches.'
            : 'These graphs are built into Front Porch. Connect ComfyUI to also list that install’s templates and saved workflows.',
        );
      })
      .catch(() => {
        if (live) setNote('Comfy’s template list could not be read.');
      });
    return () => {
      live = false;
    };
    // Read once when the sheet opens: the lists are the same for either mode.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const rows = mode === 'edit' ? edit : create;
  const others = query.trim() ? (mode === 'edit' ? create : edit).filter((r) => graphMatches(r, query)) : [];

  const choose = (picked: File | undefined) => {
    if (!picked) return;
    setError('');
    if (picked.size > MAX_GRAPH_BYTES) {
      setError('That file is too large to use.');
      return;
    }
    void picked.arrayBuffer().then((buffer) => {
      setFile({ name: picked.name, bytes: new Uint8Array(buffer) });
      setAsks(null);
    });
  };

  const send = (useFor?: Mode) => {
    if (!file) return;
    setError('');
    void uploadGraph({
      bytes: file.bytes,
      name: file.name,
      mode,
      useFor,
      password,
      totpCode: props.totpEnabled ? totp : undefined,
    })
      .then((result) => {
        if (result.stored) {
          setPassword('');
          setTotp('');
          setFile(null);
          props.onStored(result);
          return;
        }
        setAsks(result.stance);
      })
      .catch((e: unknown) => setError(e instanceof ApiError ? e.message : 'Could not use that file.'));
  };

  return (
    <div className="fp-sheet" role="dialog" aria-label="Change graph">
      <button type="button" onClick={props.onClose}>Close</button>
      <h2>{mode === 'edit' ? 'Change graph — Edit' : 'Change graph — Create'}</h2>
      <p>{note}</p>
      <p>Drop a ComfyUI graph, or an image that has one saved inside it.</p>
      <p>JSON, or a PNG from Comfy’s Save.</p>
      <input
        ref={chooser}
        aria-label="Workflow file"
        type="file"
        accept=".json,.png,application/json,image/png"
        hidden
        onChange={(e) => {
          choose(e.target.files?.[0]);
          e.target.value = '';
        }}
      />
      <button type="button" onClick={() => chooser.current?.click()}>Choose file</button>
      {file ? (
        <div>
          <p>{`${file.name} needs your web password to be used.`}</p>
          <StepUpFields
            password={password}
            onPassword={setPassword}
            totpEnabled={props.totpEnabled}
            totpCode={totp}
            onTotp={setTotp}
            reason="A graph is what ComfyUI runs on your computer — confirm your web login password."
          />
          {asks === 'unstated' ? (
            <div>
              <p>This graph doesn’t say Create or Edit.</p>
              <button type="button" disabled={!password} onClick={() => send('create')}>Use for Create</button>
              <button type="button" disabled={!password} onClick={() => send('edit')}>Use for Edit</button>
            </div>
          ) : asks ? (
            <div>
              <p>{`This graph is for ${asks === 'edit' ? 'Edit' : 'Create'}.`}</p>
              <button type="button" disabled={!password} onClick={() => send(asks)}>
                {asks === 'edit' ? 'Use it for Edit' : 'Use it for Create'}
              </button>
            </div>
          ) : (
            <button type="button" disabled={!password} onClick={() => send()}>Use this graph</button>
          )}
        </div>
      ) : null}
      {error ? <p role="alert">{error}</p> : null}
      <input aria-label="Search graphs" value={query} onChange={(e) => setQuery(e.target.value)} />
      <ul>
        {rows.filter((r) => graphMatches(r, query)).map((row) => (
          <li key={row.id}>
            <button type="button" onClick={() => props.onPick(row.id, mode)}>{row.title}</button>
            <span>{row.group}</span>
            <span>{row.detail}</span>
          </li>
        ))}
      </ul>
      {others.length > 0 ? (
        <div>
          <p>Other mode — search found these</p>
          {others.map((row) => (
            <div key={row.id}>
              <span>{row.title}</span>
              <button type="button" onClick={() => props.onPick(row.id, mode === 'edit' ? 'create' : 'edit')}>
                {mode === 'edit' ? 'Use it for Create' : 'Use it for Edit'}
              </button>
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

