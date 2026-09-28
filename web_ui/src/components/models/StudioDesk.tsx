// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api, ApiError } from '../../api/client';

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
  editWorkflowId?: string;
  editModelChoices?: Record<string, string>;
  onSave: (patch: Record<string, unknown>) => void | Promise<unknown>;
  onReady?: (ready: boolean) => void;
  /** Extra page state that should refetch Create readiness. */
  watch?: string;
}

interface CivitaiRow {
  filename: string;
  versionId: number;
  type: string;
  adult: boolean;
}

function snap(n: number): number {
  const x = Math.round(n / 64) * 64;
  if (x < 256) return 256;
  if (x > 2048) return 2048;
  return x;
}

function civitaiFailureNote(error: unknown): string {
  const message = error instanceof ApiError ? error.message.trim() : '';
  if (message.length === 0 || message.startsWith('<')) {
    return 'CivitAI download failed.';
  }
  return message;
}

/** Phone desk. Saves through the same image-config and CivitAI routes. */
export function StudioDesk(props: StudioDeskProps) {
  const [mode, setMode] = useState<'create' | 'edit'>('create');
  const [query, setQuery] = useState('');
  const [sheet, setSheet] = useState<string | null>(null);
  const [hits, setHits] = useState<string[]>([]);
  const [rows, setRows] = useState<CivitaiRow[]>([]);
  const [adult, setAdult] = useState(false);
  const [token, setToken] = useState('');
  const [graph, setGraph] = useState('');
  const [note, setNote] = useState('');
  const activeWorkflow = mode === 'edit'
    ? (props.editWorkflowId || 'qwen_image_edit')
    : props.workflowId;
  const choices = mode === 'edit' ? (props.editModelChoices ?? {}) : (props.modelChoices ?? {});
  const diffusion = choices[`${activeWorkflow}/%MODEL_DIFFUSION%`] ?? '';
  const checkpoint = choices[`${activeWorkflow}/%MODEL_CHECKPOINT%`] ?? '';
  const file = props.backend === 'comfyui'
    ? (diffusion || checkpoint || (mode === 'create' && activeWorkflow === 'sd' ? props.model : ''))
    : ((mode === 'edit' ? props.editModel : props.model) ?? '');
  const [width, height] = props.size.split('x');
  const [serverReady, setServerReady] = useState(false);
  const [savedTick, setSavedTick] = useState(0);
  const commit = (patch: Record<string, unknown>) => {
    void Promise.resolve(props.onSave(patch)).finally(() => {
      setSavedTick((n) => n + 1);
    });
  };
  useEffect(() => {
    let live = true;
    void api.get<{ ready?: boolean }>('/api/image/studio/ready?mode=create').then((body) => {
      if (live) setServerReady(body.ready === true);
    }).catch(() => {
      if (live) setServerReady(false);
    });
    return () => { live = false; };
  }, [props.backend, props.model, props.workflowId, props.comfyUrl, props.watch, file, savedTick]);
  useEffect(() => {
    props.onReady?.(serverReady);
  }, [serverReady, props.onReady]);

  const search = (kind: string) => {
    setSheet(kind);
    setQuery('');
    setNote('');
    setRows([]);
    if (kind === 'Graph search') {
      setHits(mode === 'edit'
        ? ['qwen_image_edit', 'flux_kontext']
        : ['sd', 'z_image_turbo', 'flux', 'qwen_image']);
      return;
    }
    if (kind === 'Model search' || kind === 'LoRA search') {
      if (props.backend !== 'comfyui') {
        setHits([]);
        return;
      }
      void api.get<{ deskDiscovery?: string[]; loras?: string[] }>('/api/image/comfy-catalog')
        .then((cat) => {
          setHits(kind === 'LoRA search' ? (cat.loras ?? []) : (cat.deskDiscovery ?? []));
        })
        .catch(() => setHits([]));
      return;
    }
    setHits([]);
    const q = query.trim();
    if (!q) return;
    const sheetKind = kind === 'Get a LoRA' ? 'lora' : 'model';
    void api
      .get<{ items?: { filename?: string; versionId?: number; type?: string; adult?: boolean }[]; needsCredential?: boolean }>(
        `/api/image/civitai/search?q=${encodeURIComponent(q)}&adult=${adult ? 'true' : 'false'}&sheet=${sheetKind}`,
      )
      .then((body) => {
        if (body.needsCredential) {
          setNote('Sign in to CivitAI to search adult models.');
          setHits([]);
          setRows([]);
          return;
        }
        const parsed = (body.items ?? []).flatMap((row) => {
          const filename = row.filename ?? '';
          if (!filename || typeof row.versionId !== 'number') return [];
          return [{
            filename,
            versionId: row.versionId,
            type: row.type ?? '',
            adult: row.adult === true,
          }];
        });
        setRows(parsed);
        setHits(parsed.map((row) => row.filename));
      })
      .catch(() => {
        setHits([]);
        setRows([]);
      });
  };

  const selectInstalled = async (filename: string, lora: boolean) => {
    const pick = lora
      ? props.backend === 'a1111'
        ? 'Saved to your models folder on this computer. It is in the Lora folder.'
        : 'Saved to your models folder on this computer. Pick it in LoRA search.'
      : 'Saved to your models folder on this computer. Pick it in Model search.';
    try {
      const choice = await api.post<{
        accept?: boolean;
        kind?: string;
        token?: string;
        workflowId?: string;
        loras?: { file: string; weight: number }[];
      }>('/api/image/studio/installed', {
        filename,
        lora,
        workflowId: activeWorkflow,
      });
      if (!choice.accept) {
        setNote(
          choice.kind === 'lora-full'
            ? 'Saved to your models folder on this computer. All LoRA slots are full.'
            : pick,
        );
        return;
      }
      if (choice.kind === 'lora' && choice.loras) {
        commit({ loras: choice.loras });
      } else if (choice.kind === 'comfy' && choice.token && choice.workflowId) {
        const key = `${choice.workflowId}/${choice.token}`;
        const prior = mode === 'edit' ? props.editModelChoices : props.modelChoices;
        const choices = { ...(prior ?? {}), [key]: filename };
        if (mode === 'edit') commit({ comfyEditModelChoices: choices });
        else commit({ comfyCreateModelChoices: choices });
      } else if (choice.kind === 'slot') {
        if (mode === 'edit') commit({ editModel: filename });
        else commit({ model: filename });
      } else {
        setNote(pick);
        return;
      }
      setNote('Saved to your models folder on this computer.');
      setSheet(null);
    } catch {
      setNote(pick);
    }
  };

  const saveInstalled = (name: string) => {
    if (sheet === 'Graph search') {
      if (mode === 'edit') commit({ comfyEditWorkflowId: name });
      else commit({ comfyCreateWorkflowId: name });
      setSheet(null);
      return;
    }
    if (sheet === 'LoRA search') {
      commit({ lora: name });
      setSheet(null);
      return;
    }
    if (sheet === 'Get a model' || sheet === 'Get a LoRA') {
      const row = rows.find((item) => item.filename === name);
      if (!row) {
        setNote('That row has no file to download.');
        return;
      }
      const lora = sheet === 'Get a LoRA';
      setNote('Downloading on your computer…');
      void api
        .post('/api/image/civitai/download', {
          versionId: row.versionId,
          backend: props.backend,
          adult,
          filename: row.filename,
          type: row.type,
          lora,
        })
        .then(() => selectInstalled(row.filename, lora))
        .catch((error: unknown) => setNote(civitaiFailureNote(error)));
      return;
    }
    if (props.backend === 'comfyui') {
      const token = name.toLowerCase().endsWith('.gguf') || activeWorkflow !== 'sd'
        ? '%MODEL_DIFFUSION%'
        : '%MODEL_CHECKPOINT%';
      const key = `${activeWorkflow}/${token}`;
      const prior = mode === 'edit' ? props.editModelChoices : props.modelChoices;
      const choices = { ...(prior ?? {}), [key]: name };
      if (mode === 'edit') commit({ comfyEditModelChoices: choices });
      else commit({ comfyCreateModelChoices: choices });
    } else if (mode === 'edit') {
      commit({ editModel: name });
    } else {
      commit({ model: name });
    }
    setSheet(null);
  };

  const saveSize = (nextWidth: string, nextHeight: string) => {
    const w = snap(Number(nextWidth) || 1024);
    const h = snap(Number(nextHeight) || 1024);
    commit({ size: `${w}x${h}` });
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
    if (mode === 'edit') {
      commit({
        comfyEditWorkflowId: '__uploaded__',
        comfyEditUploadedWorkflow: raw,
      });
    } else {
      commit({
        comfyCreateWorkflowId: '__uploaded__',
        comfyCreateUploadedWorkflow: raw,
      });
    }
    setNote('');
  };

  return (
    <section className="studio-desk">
      <label>
        Backend
        <select value={props.backend} onChange={(e) => commit({ backend: e.target.value })}>
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
            if (props.backend === 'comfyui') commit({ comfyUrl: value });
            else if (props.backend === 'a1111') commit({ localUrl: value });
            else if (props.backend === 'drawthings') commit({ drawThingsHost: value });
            else commit({ remoteApiUrl: value });
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
        <input aria-label="Steps" defaultValue={String(props.steps)} onBlur={(e) => commit({ steps: Number(e.target.value) })} />
      </label>
      <label>
        Sampler
        <input aria-label="Sampler" defaultValue={props.sampler} onBlur={(e) => commit({ sampler: e.target.value })} />
      </label>
      <button type="button" onClick={() => setSheet('CivitAI sign-in')}>CivitAI sign-in</button>
      <button type="button" onClick={() => search('Get a model')}>Get a model</button>
      <button type="button" onClick={() => search('Get a LoRA')}>Get a LoRA</button>
      <label>
        Adult
        <input type="checkbox" role="switch" checked={adult} onChange={(e) => setAdult(e.target.checked)} />
      </label>
      <button type="button" disabled={!serverReady}>Generate</button>
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
              <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
            ))}
          </ul>
          {query.trim() && sheet !== 'Get a model' && sheet !== 'Get a LoRA' ? (
            <button type="button" onClick={() => saveInstalled(query.trim())}>Use {query.trim()}</button>
          ) : null}
        </div>
      )}
    </section>
  );
}
