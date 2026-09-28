// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api } from '../../api/client';

export interface StudioDeskProps {
  backend: string;
  model: string;
  editModel?: string;
  size: string;
  steps: number;
  sampler: string;
  workflowId: string;
  modelChoices?: Record<string, string>;
  comfyUrl: string;
  localUrl: string;
  drawThingsHost: string;
  remoteUrl: string;
  onSave: (patch: Record<string, unknown>) => void;
}

function snap(n: number): number {
  const x = Math.round(n / 64) * 64;
  if (x < 256) return 256;
  if (x > 2048) return 2048;
  return x;
}

/** Phone desk. Saves through the same image-config and CivitAI routes. */
export function StudioDesk(props: StudioDeskProps) {
  const [mode, setMode] = useState<'create' | 'edit'>('create');
  const [query, setQuery] = useState('');
  const [sheet, setSheet] = useState<string | null>(null);
  const [hits, setHits] = useState<string[]>([]);
  const [adult, setAdult] = useState(false);
  const [token, setToken] = useState('');
  const [graph, setGraph] = useState('');
  const [note, setNote] = useState('');
  const [catalogReachable, setCatalogReachable] = useState<boolean | null>(null);
  const diffusion = props.modelChoices?.[`${props.workflowId}/%MODEL_DIFFUSION%`] ?? '';
  const checkpoint = props.modelChoices?.[`${props.workflowId}/%MODEL_CHECKPOINT%`] ?? '';
  const file = props.backend === 'comfyui'
    ? (diffusion || checkpoint || (props.workflowId === 'sd' ? props.model : ''))
    : ((mode === 'edit' ? props.editModel : props.model) ?? '');
  const [width, height] = props.size.split('x');
  const generateOn = props.backend === 'comfyui'
    ? catalogReachable === true && file.trim().length > 0
    : file.trim().length > 0;

  useEffect(() => {
    if (props.backend !== 'comfyui') {
      setCatalogReachable(null);
      return;
    }
    let live = true;
    void api.get('/api/image/comfy-catalog').then(() => {
      if (live) setCatalogReachable(true);
    }).catch(() => {
      if (live) setCatalogReachable(false);
    });
    return () => { live = false; };
  }, [props.backend, props.comfyUrl]);

  const search = (kind: string) => {
    setSheet(kind);
    setQuery('');
    setHits([]);
    const q = query.trim();
    if (!q) return;
    void api
      .get<{ items?: { name?: string; filename?: string }[] }>(
        `/api/image/civitai/search?q=${encodeURIComponent(q)}&adult=${adult ? 'true' : 'false'}&sheet=${kind === 'Get a LoRA' || kind === 'LoRA search' ? 'lora' : 'model'}`,
      )
      .then((body) => {
        setHits((body.items ?? []).map((row) => row.filename || row.name || '').filter(Boolean));
      })
      .catch(() => setHits([]));
  };

  const saveModel = (name: string) => {
    if (props.backend === 'comfyui') {
      props.onSave({
        comfyCreateWorkflowId: props.workflowId,
        comfyCreateModelChoices: { [`${props.workflowId}/%MODEL_DIFFUSION%`]: name },
      });
    } else if (mode === 'edit') {
      props.onSave({ editModel: name });
    } else {
      props.onSave({ model: name });
    }
    setSheet(null);
  };

  const saveSize = (nextWidth: string, nextHeight: string) => {
    const w = snap(Number(nextWidth) || 1024);
    const h = snap(Number(nextHeight) || 1024);
    props.onSave({ size: `${w}x${h}` });
  };

  const saveKey = () => {
    const trimmed = token.trim();
    if (!trimmed) return;
    void api.post('/api/image/civitai/credential', { token: trimmed }).catch(() => {
      setNote('Could not save the API key.');
    });
  };

  const useGraph = () => {
    const raw = graph.trim();
    if (!raw.startsWith('{')) {
      setNote('That file has no workflow.');
      return;
    }
    props.onSave({
      comfyCreateWorkflowId: '__uploaded__',
      comfyCreateUploadedWorkflow: raw,
    });
    setNote('');
  };

  return (
    <section className="studio-desk">
      <label>
        Backend
        <select value={props.backend} onChange={(e) => props.onSave({ backend: e.target.value })}>
          <option value="remote">Remote</option>
          <option value="comfyui">ComfyUI</option>
          <option value="a1111">Automatic1111</option>
          <option value="drawthings">Draw Things</option>
        </select>
      </label>
      <label>
        {props.backend === 'comfyui' ? 'ComfyUI URL' : props.backend === 'a1111' ? 'Automatic1111 URL' : props.backend === 'drawthings' ? 'Draw Things host' : 'Remote URL'}
        <input
          key={props.backend}
          defaultValue={props.backend === 'comfyui' ? props.comfyUrl : props.backend === 'a1111' ? props.localUrl : props.backend === 'drawthings' ? props.drawThingsHost : props.remoteUrl}
          onBlur={(e) => {
            const value = e.target.value;
            if (props.backend === 'comfyui') props.onSave({ comfyUrl: value });
            else if (props.backend === 'a1111') props.onSave({ localUrl: value });
            else if (props.backend === 'drawthings') props.onSave({ drawThingsHost: value });
            else props.onSave({ remoteApiUrl: value });
          }}
        />
      </label>
      <div role="tablist">
        <button type="button" role="tab" onClick={() => setMode('create')}>Create</button>
        <button type="button" role="tab" onClick={() => setMode('edit')}>Edit</button>
      </div>
      <p>{file || 'No model chosen'}</p>
      <button type="button" onClick={() => search('Model search')}>Model search</button>
      <button type="button" onClick={() => search('Graph search')}>Graph search</button>
      <button type="button" onClick={() => setSheet('Graph upload')}>Graph upload</button>
      <button type="button" onClick={() => search('LoRA search')}>LoRA search</button>
      <label>
        Width
        <input aria-label="Width" defaultValue={width || '1024'} onBlur={(e) => saveSize(e.target.value, height || '1024')} />
      </label>
      <label>
        Height
        <input aria-label="Height" defaultValue={height || '1024'} onBlur={(e) => saveSize(width || '1024', e.target.value)} />
      </label>
      <label>
        Steps
        <input aria-label="Steps" defaultValue={String(props.steps)} onBlur={(e) => props.onSave({ steps: Number(e.target.value) })} />
      </label>
      <label>
        Sampler
        <input aria-label="Sampler" defaultValue={props.sampler} onBlur={(e) => props.onSave({ sampler: e.target.value })} />
      </label>
      <button type="button" onClick={() => setSheet('CivitAI sign-in')}>CivitAI sign-in</button>
      <button type="button" onClick={() => search('Get a model')}>Get a model</button>
      <button type="button" onClick={() => search('Get a LoRA')}>Get a LoRA</button>
      <label>
        Adult
        <input type="checkbox" role="switch" checked={adult} onChange={(e) => setAdult(e.target.checked)} />
      </label>
      <button type="button" disabled={!generateOn}>Generate</button>
      {note ? <p>{note}</p> : null}
      {sheet === 'CivitAI sign-in' && (
        <label>
          API key
          <input value={token} onChange={(e) => setToken(e.target.value)} onBlur={saveKey} />
        </label>
      )}
      {sheet === 'Graph upload' && (
        <label>
          Workflow JSON
          <textarea value={graph} onChange={(e) => setGraph(e.target.value)} onBlur={useGraph} />
        </label>
      )}
      {sheet && sheet !== 'CivitAI sign-in' && sheet !== 'Graph upload' && (
        <div>
          <input aria-label="Search" value={query} onChange={(e) => setQuery(e.target.value)} />
          <button type="button" onClick={() => search(sheet)}>Search</button>
          <ul>
            {hits.map((item) => (
              <li key={item}><button type="button" onClick={() => saveModel(item)}>{item}</button></li>
            ))}
          </ul>
          {query.trim() ? <button type="button" onClick={() => saveModel(query.trim())}>Use {query.trim()}</button> : null}
        </div>
      )}
    </section>
  );
}
