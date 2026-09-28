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
  loras?: { file: string; weight: number }[];
  onSave: (patch: Record<string, unknown>) => void | Promise<unknown>;
  onReady?: (ready: boolean) => void;
  /** Extra page state that should refetch Create readiness. */
  watch?: string;
  cfg?: number;
  scheduler?: string;
  prompt?: string;
  onPrompt?: (value: string) => void;
  onGenerate?: () => void;
  generateError?: string;
  busy?: boolean;
  loraFacts?: Record<string, { family: string; meta?: boolean }>;
}

function workflowForFile(edit: boolean, name: string): string {
  const family = familyOf(name);
  const gguf = name.toLowerCase().endsWith('.gguf');
  if (edit) {
    return family === 'flux' || family === 'kontext' ? 'flux_kontext' : 'qwen_image_edit';
  }
  if (family === 'zImage') return 'z_image_turbo';
  if (family === 'flux' || family === 'kontext') return 'flux';
  if (family === 'qwen') return 'qwen_image';
  return gguf ? 'z_image_turbo' : 'sd';
}

function familyOf(name: string): string {
  const s = name.toLowerCase();
  if (s.includes('kontext')) return 'kontext';
  if (/z[ _-]?image/.test(s)) return 'zImage';
  if (s.includes('qwen')) return 'qwen';
  if (s.includes('flux')) return 'flux';
  if (s.includes('pony')) return 'pony';
  if (/sd[ _-]?xl|xl(?![a-z])|illustrious/.test(s)) return 'sdxl';
  return 'unknown';
}

function slotBadge(
  file: string,
  modelName: string,
  facts?: Record<string, { family: string; meta?: boolean }>,
): string {
  const fact = facts?.[file];
  const lora = fact?.family || familyOf(file);
  const model = familyOf(modelName);
  if (lora !== 'unknown' && lora === model) return 'match';
  const pony =
    (lora === 'pony' && model === 'sdxl') || (lora === 'sdxl' && model === 'pony');
  if (lora === 'unknown' || model === 'unknown' || pony || !fact?.meta) return 'likely';
  return 'other base';
}

interface CivitaiRow {
  filename: string;
  versionId: number;
  type: string;
  adult: boolean;
  name?: string;
  downloads?: number;
  preview?: string;
  description?: string;
}

function snap(n: number): number {
  const x = Math.round(n / 64) * 64;
  if (x < 256) return 256;
  if (x > 2048) return 2048;
  return x;
}

interface GraphRow {
  id: string;
  title: string;
  detail: string;
  group: string;
}

const builtInCreate: GraphRow[] = [
  { id: 'sd', title: 'SD / SDXL / Pony', detail: 'Built into Front Porch', group: 'Text to image graphs' },
  { id: 'flux', title: 'Flux', detail: 'Built into Front Porch', group: 'Text to image graphs' },
  { id: 'qwen_image', title: 'Qwen-Image', detail: 'Built into Front Porch', group: 'Text to image graphs' },
  { id: 'z_image_turbo', title: 'Z-Image Turbo', detail: 'Built into Front Porch', group: 'Text to image graphs' },
];

const builtInEdit: GraphRow[] = [
  { id: 'qwen_image_edit', title: 'Qwen-Image-Edit', detail: 'Built into Front Porch', group: 'Edit graphs' },
  { id: 'flux_kontext', title: 'Flux Kontext', detail: 'Built into Front Porch', group: 'Edit graphs' },
];

function workflowJsonFromBytes(bytes: Uint8Array): string | null {
  const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes).trim();
  if (text.startsWith('{')) {
    try {
      const decoded = JSON.parse(text) as unknown;
      if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) return text;
    } catch {
      return null;
    }
  }
  if (bytes.length < 8 || bytes[0] !== 137 || bytes[1] !== 80) return null;
  for (const raw of [pngText(bytes, 'prompt'), pngText(bytes, 'workflow')]) {
    if (!raw) continue;
    try {
      const decoded = JSON.parse(raw) as unknown;
      if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) return raw;
    } catch {
      /* the other chunk may still be the workflow */
    }
  }
  return null;
}

function pngText(bytes: Uint8Array, keyword: string): string | null {
  let offset = 8;
  while (offset + 12 <= bytes.length) {
    const length = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
    const type = String.fromCharCode(bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7]);
    const start = offset + 8;
    const end = start + length;
    if (length < 0 || end + 4 > bytes.length) return null;
    if (type === 'tEXt') {
      const data = bytes.slice(start, end);
      const zero = data.indexOf(0);
      if (zero > 0 && new TextDecoder().decode(data.slice(0, zero)) === keyword) {
        return new TextDecoder().decode(data.slice(zero + 1));
      }
    }
    if (type === 'IEND') return null;
    offset = end + 4;
  }
  return null;
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
  const [civitaiDetail, setCivitaiDetail] = useState<CivitaiRow | null>(null);
  const [adult, setAdult] = useState(false);
  const [token, setToken] = useState('');
  const [graphs, setGraphs] = useState<GraphRow[]>([]);
  const [graphNote, setGraphNote] = useState('');
  const [note, setNote] = useState('');
  const [advanced, setAdvanced] = useState(false);
  const [overrideFamily, setOverrideFamily] = useState('');
  const [subject, setSubject] = useState('character');
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
  const [loraBlock, setLoraBlock] = useState<{ lora: string; primary: string; family: string } | null>(null);
  const [savedTick, setSavedTick] = useState(0);
  const commit = (patch: Record<string, unknown>) => {
    void Promise.resolve(props.onSave(patch)).finally(() => {
      setSavedTick((n) => n + 1);
    });
  };
  useEffect(() => {
    let live = true;
    void api.get<{ ready?: boolean; kind?: string; blockedLora?: string | null; primary?: string; loraFamily?: string }>('/api/image/studio/ready?mode=create').then((body) => {
      if (!live) return;
      setServerReady(body.ready === true);
      setLoraBlock(
        body.kind === 'loraMismatch' && body.blockedLora && body.primary
          ? { lora: body.blockedLora, primary: body.primary, family: body.loraFamily ?? '' }
          : null,
      );
    }).catch(() => {
      if (!live) return;
      setServerReady(false);
      setLoraBlock(null);
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
      openGraphs();
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
      .get<{ items?: { filename?: string; versionId?: number; type?: string; adult?: boolean; name?: string; downloads?: number; previewUrl?: string; description?: string }[]; needsCredential?: boolean }>(
        `/api/image/civitai/search?q=${encodeURIComponent(q)}&adult=${adult ? 'true' : 'false'}&sheet=${sheetKind}`,
      )
      .then((body) => {
        if (body.needsCredential) {
          setNote('Paste an API key to search adult models.');
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
            name: row.name,
            downloads: row.downloads ?? 0,
            preview: row.previewUrl,
            description: row.description,
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
        : 'Saved to your models folder on this computer. Pick it with Add.'
      : 'Saved to your models folder on this computer. Pick it with Change model.';
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
        workflowId: lora ? activeWorkflow : workflowForFile(mode === 'edit', filename),
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
        const id = choice.workflowId || workflowForFile(mode === 'edit', filename);
        if (mode === 'edit') {
          commit({ comfyEditWorkflowId: id, comfyEditModelChoices: choices });
        } else {
          commit({ comfyCreateWorkflowId: id, comfyCreateModelChoices: choices });
        }
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
      const chosen = file.toLowerCase().endsWith('.gguf') && name === 'sd'
        ? workflowForFile(mode === 'edit', file)
        : name;
      if (mode === 'edit') commit({ comfyEditWorkflowId: chosen });
      else commit({ comfyCreateWorkflowId: chosen });
      setSheet(null);
      return;
    }
    if (sheet === 'LoRA search') {
      const slots = [...(props.loras ?? [])];
      while (slots.length < 8) slots.push({ file: '', weight: 0.8 });
      const index = slots.findIndex((slot) => !slot.file.trim());
      if (index < 0) {
        setNote('All LoRA slots are full. Clear one on the computer to add another.');
        return;
      }
      slots[index] = { file: name, weight: slots[index].weight || 0.8 };
      commit({ loras: slots.slice(0, 8) });
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

  const openGraphs = () => {
    setSheet('Graph search');
    setQuery('');
    const built = mode === 'edit' ? builtInEdit : builtInCreate;
    if (props.backend !== 'comfyui') {
      setGraphs(built);
      setGraphNote('These graphs are built into Front Porch. Connect ComfyUI to also list that install’s templates and saved workflows.');
      return;
    }
    setGraphs(built);
    setGraphNote('Reading this Comfy’s templates…');
    void api.get<{ graphs?: GraphRow[]; editGraphs?: GraphRow[] }>('/api/image/comfy-catalog').then((cat) => {
      const live = mode === 'edit' ? cat.editGraphs : cat.graphs;
      if (!live || live.length === 0) {
        setGraphs(built);
        setGraphNote('Comfy’s template list could not be read. The names below are built into Front Porch.');
        return;
      }
      setGraphs(live);
      setGraphNote('The first group is built into Front Porch. Saved workflows are only listed for the mode their graph matches.');
    }).catch(() => {
      setGraphs(built);
      setGraphNote('Comfy’s template list could not be read. The names below are built into Front Porch.');
    });
  };

  const readWorkflowFile = (file: File) => {
    void file.arrayBuffer().then((buffer) => {
      const json = workflowJsonFromBytes(new Uint8Array(buffer));
      if (!json) {
        const png = file.type === 'image/png' || file.name.toLowerCase().endsWith('.png');
        setNote(
          png
            ? 'That image has no ComfyUI workflow saved inside it.'
            : 'That file isn’t a ComfyUI graph.',
        );
        return;
      }
      if (mode === 'edit') {
        commit({ comfyEditWorkflowId: '__uploaded__', comfyEditUploadedWorkflow: json });
      } else {
        commit({ comfyCreateWorkflowId: '__uploaded__', comfyCreateUploadedWorkflow: json });
      }
      setNote(`${file.name} is the workflow for this ${mode === 'edit' ? 'edit' : 'portrait'}.`);
      setSheet(null);
    });
  };

  const filled = (props.loras ?? []).filter((slot) => slot.file.trim());
  const modelFamily = familyOf(file);
  const certain = overrideFamily === modelFamily
    ? undefined
    : filled.find((slot) => slotBadge(slot.file, file, props.loraFacts) === 'other base');
  const serverBlocked = !certain && loraBlock != null && overrideFamily !== (loraBlock.family || modelFamily);
  const ready = certain || serverBlocked ? false : serverReady;
  const cfg = props.cfg ?? 1;
  const scheduler = props.scheduler ?? 'Automatic';
  const summary = `${props.steps} steps · cfg ${cfg} · ${props.sampler} · ${scheduler}`;
  const sentW = Number(width) || 1024;
  const sentH = Number(height) || 1024;
  const url = props.backend === 'comfyui'
    ? props.comfyUrl
    : props.backend === 'a1111'
      ? props.localUrl
      : props.backend === 'drawthings'
        ? props.drawThingsHost
        : props.remoteUrl;
  const backendName = props.backend === 'comfyui'
    ? 'ComfyUI'
    : props.backend === 'a1111'
      ? 'Automatic1111'
      : props.backend === 'drawthings'
        ? 'Draw Things'
        : 'Remote';
  const why = file.toLowerCase().endsWith('.gguf')
    ? `Workflow · GGUF · chosen for this file · ${activeWorkflow}`
    : activeWorkflow === '__uploaded__'
      ? 'Workflow · your file · workflow · 0 nodes'
      : `Workflow · ${mode === 'edit' ? 'Edit' : 'Text to image'} · ${activeWorkflow}`;
  const familyLabel = file ? (modelFamily === 'zImage' ? 'Z-Image' : modelFamily === 'qwen' ? 'Qwen' : modelFamily === 'unknown' ? 'Model' : modelFamily) : 'No model chosen';
  const checkpointOnly = activeWorkflow === 'sd';
  const otherGraphs = (mode === 'edit' ? builtInCreate : builtInEdit).filter((row) => {
    const q = query.trim().toLowerCase();
    return q.length > 0 && (row.title.toLowerCase().includes(q) || row.id.toLowerCase().includes(q));
  });

  return (
    <section className="studio-desk">
      <style>{`
        .fp-desk-body { display: flex; gap: 16px; align-items: flex-start; }
        .fp-desk-rail, .fp-desk-stove { flex: 1; min-width: 0; }
        @media (max-width: 720px) {
          .fp-desk-body { flex-direction: column; }
        }
      `}</style>
      <div className="fp-desk-body">
        <div className="fp-desk-rail" data-region="rail">
          <div>Subject</div>
          <button type="button" onClick={() => setSubject('free')}>Freeform</button>
          <button type="button" onClick={() => setSubject('char')}>Character</button>
          <button type="button" onClick={() => setSubject('persona')}>Your persona</button>
          <div>
            <span>Prompt</span>
            <button type="button">Write it for me</button>
          </div>
          <textarea
            aria-label="Prompt"
            value={props.prompt ?? ''}
            onChange={(e) => props.onPrompt?.(e.target.value)}
          />
          <p>
            {mode === 'edit'
              ? 'Portrait in this chat. Edit sends an instruction with this picture.'
              : 'Start from a picture — optional. A reference here varies the Create model. It does not switch you to Edit.'}
          </p>
          <button type="button">Expression pack</button>
          <p>{mode === 'edit' ? 'Pack uses this edit model.' : 'Pack uses this Create model to vary the portrait.'}</p>
          <span hidden>{subject}</span>
        </div>
        <div className="fp-desk-stove" data-region="stove">
          <div>Connection</div>
          <div>{backendName}</div>
          <div>{url}</div>
          <details>
            <summary>Change…</summary>
            <button type="button" onClick={() => commit({ backend: 'remote' })}>Remote</button>
            <button type="button" onClick={() => commit({ backend: 'comfyui' })}>ComfyUI</button>
            <button type="button" onClick={() => commit({ backend: 'a1111' })}>Automatic1111</button>
            <button type="button" onClick={() => commit({ backend: 'drawthings' })}>Draw Things</button>
          </details>
          <div>
            <button type="button" onClick={() => setMode('create')}>Create</button>
            <span>make a new portrait</span>
            <button type="button" onClick={() => setMode('edit')}>Edit</button>
            <span>change this portrait</span>
          </div>
          <div>Model</div>
          <strong>{familyLabel}</strong>
          <div>{file || 'No model chosen'}</div>
          <p>{why}</p>
          <button type="button" onClick={() => search('Model search')}>Change model</button>
          <button type="button" onClick={() => search('Get a model')}>Get a model from CivitAI</button>
          {checkpointOnly ? <p>This checkpoint graph has no text encoder or VAE slot.</p> : (
            <>
              <p>This graph also loads</p>
              <p>These files do not set the LoRA family. The text encoder can be Qwen while the model is Z-Image.</p>
            </>
          )}
          <div>LoRA</div>
          {filled.map((slot) => (
            <div key={slot.file}>
              <span>{slot.file}</span>
              <span>{slotBadge(slot.file, file, props.loraFacts)}</span>
              <label>
                Weight
                <input
                  aria-label={`Weight ${slot.file}`}
                  type="number"
                  min={0}
                  max={1}
                  step={0.05}
                  defaultValue={String(slot.weight)}
                  onBlur={(e) => {
                    const weight = Number(e.target.value);
                    const next = (props.loras ?? []).map((row) =>
                      row.file === slot.file ? { ...row, weight } : row,
                    );
                    commit({ loras: next });
                  }}
                />
              </label>
            </div>
          ))}
          {certain ? (
            <p>
              Generate stays off until you pick a matching LoRA or press Use anyway.
              <button
                type="button"
                onClick={() => {
                  setOverrideFamily(modelFamily);
                  commit({ loraOverrideFamily: modelFamily });
                }}
              >
                Use anyway
              </button>
            </p>
          ) : null}
          <button type="button" onClick={() => search('LoRA search')}>Add</button>
          <button type="button" onClick={() => search('Get a LoRA')}>Get a LoRA from CivitAI</button>
          <div>Size</div>
          {['512×512', '768×768', '1024×1024', '1536×1024', '1024×1536'].map((label) => (
            <button
              key={label}
              type="button"
              onClick={() => {
                const [cw, ch] = label.split('×');
                saveSize(cw, ch);
              }}
            >
              {label}
            </button>
          ))}
          <label>
            Width
            <input key={`w-${props.size}`} aria-label="Width" defaultValue={width || '1024'} onBlur={(e) => saveSize(e.target.value, height || '1024')} />
          </label>
          <label>
            Height
            <input key={`h-${props.size}`} aria-label="Height" defaultValue={height || '1024'} onBlur={(e) => saveSize(width || '1024', e.target.value)} />
          </label>
          <p>{`Sends ${sentW}×${sentH}. Each side snaps to a multiple of 64, from 256 to 2048.`}</p>
          <button type="button" onClick={() => setAdvanced((open) => !open)}>
            {advanced ? `Advanced ▾ ${summary}` : `Advanced ▸ ${summary}`}
          </button>
          {advanced ? <button type="button" onClick={() => openGraphs()}>Change graph</button> : null}
          {advanced && props.backend !== 'drawthings' ? (
            <>
              <label>Steps<input aria-label="Steps" defaultValue={String(props.steps)} onBlur={(e) => commit({ steps: Number(e.target.value) })} /></label>
              <label>CFG<input aria-label="CFG" defaultValue={String(cfg)} onBlur={(e) => commit({ cfgScale: Number(e.target.value) })} /></label>
              <label>Sampler<input aria-label="Sampler" defaultValue={props.sampler} onBlur={(e) => commit({ sampler: e.target.value })} /></label>
              <label>Scheduler<input aria-label="Scheduler" defaultValue={scheduler} onBlur={(e) => commit({ scheduler: e.target.value })} /></label>
            </>
          ) : null}
          {advanced && props.backend === 'drawthings' ? (
            <label>
              Sampler
              <select aria-label="Draw Things sampler" defaultValue={props.sampler} onChange={(e) => commit({ sampler: e.target.value })}>
                <option>Euler a Trailing</option>
              </select>
            </label>
          ) : null}
          <p>{props.busy ? 'Generating…' : ready ? 'Ready to generate.' : certain || serverBlocked ? `Not ready — LoRA architecture does not match ${file}.` : 'Not ready.'}</p>
          <button type="button" disabled={!ready || props.busy === true} onClick={() => props.onGenerate?.()}>Generate</button>
          {props.generateError ? <p>{props.generateError}</p> : null}
          {note ? <p>{note}</p> : null}
        </div>
      </div>
      {sheet === 'Graph search' && (
        <div>
          <h2>{mode === 'edit' ? 'Change graph — Edit' : 'Change graph — Create'}</h2>
          <p>{graphNote}</p>
          <p>Drop a ComfyUI graph, or an image that has one saved inside it.</p>
          <p>JSON, or a PNG from Comfy’s Save.</p>
          <input
            aria-label="Workflow file"
            type="file"
            accept=".json,.png,application/json,image/png"
            onChange={(event) => {
              const picked = event.target.files?.[0];
              if (picked) readWorkflowFile(picked);
            }}
          />
          <button type="button">Choose file</button>
          <input aria-label="Search graphs" value={query} onChange={(e) => setQuery(e.target.value)} />
          <ul>
            {graphs.filter((row) => {
              const q = query.trim().toLowerCase();
              return !q || row.title.toLowerCase().includes(q) || row.detail.toLowerCase().includes(q);
            }).map((row) => (
              <li key={row.id}>
                <button type="button" onClick={() => saveInstalled(row.id)}>{row.title}</button>
                <span>{row.group}</span>
                <span>{row.detail}</span>
              </li>
            ))}
          </ul>
          {otherGraphs.length > 0 ? (
            <div>
              <p>Other mode — search found these</p>
              {otherGraphs.map((row) => (
                <div key={row.id}>
                  <span>{row.title}</span>
                  <button type="button" onClick={() => {
                    if (mode === 'edit') commit({ comfyCreateWorkflowId: row.id });
                    else commit({ comfyEditWorkflowId: row.id });
                  }}>{mode === 'edit' ? 'Use it for Create' : 'Use it for Edit'}</button>
                </div>
              ))}
            </div>
          ) : null}
        </div>
      )}
      {(sheet === 'Get a model' || sheet === 'Get a LoRA') && (
        <div>
          <h2>{civitaiDetail?.name || (sheet === 'Get a LoRA' ? 'Get a LoRA from CivitAI' : 'Get a model from CivitAI')}</h2>
          {sheet === 'Get a LoRA' ? null : <button type="button">On this computer</button>}
          <button type="button">CivitAI</button>
          <label>
            <input type="checkbox" checked={adult} onChange={(e) => setAdult(e.target.checked)} />
            Include adult models from civitai.red
          </label>
          <label>
            API key
            <input value={token} onChange={(e) => setToken(e.target.value)} onBlur={saveKey} />
          </label>
          <input aria-label="Search" value={query} onChange={(e) => setQuery(e.target.value)} />
          <button type="button" onClick={() => search(sheet)}>Search</button>
          {civitaiDetail ? (
            <div>
              {civitaiDetail.preview ? (
                <img alt="" src={civitaiDetail.preview} style={{ width: '100%', objectFit: 'contain', maxHeight: 420 }} />
              ) : null}
              <p>{(civitaiDetail.downloads ?? 0).toLocaleString()} downloads</p>
              <p>{civitaiDetail.description || 'CivitAI did not send a description.'}</p>
              <button type="button" onClick={() => setCivitaiDetail(null)}>Back</button>
              <button type="button" onClick={() => saveInstalled(civitaiDetail.filename)}>Download</button>
            </div>
          ) : sheet === 'Get a LoRA' ? (
            rows.map((row) => (
              <button
                key={row.filename}
                type="button"
                onClick={() => setCivitaiDetail(row)}
                style={{ display: 'flex', gap: 8, textAlign: 'left', margin: '8px 0' }}
              >
                {row.preview ? <img alt="" src={row.preview} width={88} height={88} style={{ objectFit: 'cover' }} /> : null}
                <span>
                  <strong>{row.name || row.filename}</strong>
                  <span>{(row.downloads ?? 0).toLocaleString()} downloads</span>
                </span>
              </button>
            ))
          ) : (
            <ul>
              {hits.map((item) => (
                <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
              ))}
            </ul>
          )}
          {note ? <p>{note}</p> : null}
        </div>
      )}
      {sheet === 'Model search' && (
        <div>
          <h2>{mode === 'edit' ? 'Change model — Edit' : 'Change model — Create'}</h2>
          <input aria-label="Search" placeholder="Search families or files" value={query} onChange={(e) => setQuery(e.target.value)} />
          <button type="button" onClick={() => search(sheet)}>Search</button>
          <ul>
            {hits.map((item) => (
              <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
            ))}
          </ul>
          {query.trim() ? (
            <button type="button" onClick={() => saveInstalled(query.trim())}>Use {query.trim()}</button>
          ) : null}
        </div>
      )}
      {sheet === 'LoRA search' && (
        <div>
          <h2>LoRA</h2>
          <p>Matches this model</p>
          <p>Other bases</p>
          <ul>
            {filled.map((slot) => (
              <li key={slot.file}>{slot.file}</li>
            ))}
          </ul>
          <input aria-label="Search" value={query} onChange={(e) => setQuery(e.target.value)} />
          <button type="button" onClick={() => search(sheet)}>Search</button>
          <ul>
            {hits.map((item) => (
              <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
