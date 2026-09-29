// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState, type ReactNode } from 'react';
import { api, ApiError } from '../../api/client';
import { civitaiBaseGroups, filterCivitaiBases, visibleCivitaiBase } from './civitaiBases';

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
  drawThingsSampler?: number;
  prompt?: string;
  onPrompt?: (value: string) => void;
  onGenerate?: () => void;
  generateError?: string;
  busy?: boolean;
  /** Finished picture. Wide desks place it under Expression pack. */
  result?: ReactNode;
}

function workflowForFile(edit: boolean, name: string): string {
  const family = familyOf(name);
  const gguf = name.toLowerCase().endsWith('.gguf');
  if (edit) {
    return family === 'flux' || family === 'kontext' ? 'flux_kontext' : 'qwen_image_edit';
  }
  if (family === 'zImage') return 'z_image_turbo';
  if (family === 'flux' || family === 'kontext') return 'flux';
  if (family === 'qwen') return /2[._]1/.test(name.toLowerCase()) ? 'qwen_image_21' : 'qwen_image';
  return gguf ? 'z_image_turbo' : 'sd';
}

function isQwen21(name: string): boolean {
  const s = name.toLowerCase();
  return s.includes('qwen') && /2[._]1/.test(s);
}

/** Qwen-Image 2.1 needs Qwen3-VL 8B. A 4B file and the vision projector are not it. */
function qwen3Vl8b(name: string): boolean {
  const base = name.trim().toLowerCase().split('/').pop() ?? '';
  if (base.includes('mmproj') || base.includes('pe_t2i') || base.includes('pe_i2i') || base.includes('prompt_enhance')) {
    return false;
  }
  const vl = base.includes('qwen3vl')
    || base.includes('qwen3_vl')
    || base.includes('qwen_3vl')
    || base.includes('qwen_3_vl')
    || base.includes('qwen3-vl')
    || base.includes('qwen-3-vl');
  if (!vl) return false;
  return /(^|[^a-z0-9])8b($|[^a-z0-9])/.test(base);
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

function graphTypes(json: string): Set<string> {
  const types = new Set<string>();
  let decoded: unknown;
  try {
    decoded = JSON.parse(json);
  } catch {
    return types;
  }
  if (!decoded || typeof decoded !== 'object') return types;
  const take = (node: unknown) => {
    if (!node || typeof node !== 'object') return;
    const type = (node as { class_type?: unknown; type?: unknown }).class_type
      ?? (node as { type?: unknown }).type;
    if (typeof type === 'string' && type) types.add(type);
  };
  const record = decoded as { nodes?: unknown };
  if (Array.isArray(record.nodes)) record.nodes.forEach(take);
  Object.values(decoded as Record<string, unknown>).forEach(take);
  return types;
}

function workflowNodeCount(json: string): number {
  const types = graphTypes(json);
  return types.size === 0 ? 0 : (() => {
    try {
      const decoded = JSON.parse(json) as { nodes?: unknown };
      if (Array.isArray(decoded.nodes)) return decoded.nodes.length;
      return Object.values(decoded).filter((node) => {
        return !!node && typeof node === 'object' && ('class_type' in (node as object) || 'type' in (node as object));
      }).length;
    } catch {
      return 0;
    }
  })();
}

/** Same Create / Edit split the desktop uses for a saved graph. */
export function graphStance(json: string): 'edit' | 'create' | 'unstated' {
  const types = graphTypes(json);
  if (types.size === 0) return 'unstated';
  const loads = types.has('LoadImage') || types.has('LoadImageMask');
  if (loads) {
    for (const type of types) {
      if (type.includes('ImageEdit') || type.includes('Kontext') || type === 'ReferenceLatent') {
        return 'edit';
      }
    }
  }
  const marks = ['KSampler', 'EmptyLatentImage', 'EmptySD3LatentImage', 'UNETLoader', 'UnetLoaderGGUF', 'CheckpointLoaderSimple', 'VAEDecode'];
  if (marks.some((mark) => types.has(mark))) return 'create';
  return 'unstated';
}

function supportRows(
  workflowId: string,
  choices: Record<string, string>,
  primary = '',
): { role: string; token: string; file: string }[] {
  const tokens = workflowId === 'flux' || workflowId === 'flux_kontext'
    ? [['Text encoder', '%MODEL_CLIP1%'], ['Text encoder', '%MODEL_CLIP2%'], ['VAE', '%MODEL_VAE%']]
    : workflowId === 'sd' || workflowId === '__uploaded__'
      ? []
      : [['Text encoder', '%MODEL_CLIP%'], ['VAE', '%MODEL_VAE%']];
  return tokens.map(([role, token]) => {
    const raw = (choices[`${workflowId}/${token}`] ?? '').trim();
    const hide = primary !== ''
      && (token.includes('CLIP') || token.includes('VAE'))
      && raw !== ''
      && !supportFits(primary, raw, token);
    return { role, token, file: hide ? '' : raw };
  });
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

const drawThingsSamplers: [string, number][] = [
  ['DDIM Trailing', 16],
  ['UniPC Trailing', 17],
  ['Euler a Trailing', 10],
  ['DPM++ 2M Trailing', 15],
  ['DPM++ SDE Trailing', 11],
  ['UniPC AYS', 18],
  ['Euler a AYS', 13],
  ['DPM++ 2M AYS', 12],
  ['DPM++ SDE AYS', 14],
  ['DPM++ 2M Karras', 0],
  ['DPM++ SDE Karras', 4],
  ['Euler a', 1],
  ['UniPC', 5],
  ['DDIM', 2],
  ['PLMS', 3],
  ['LCM', 6],
  ['TCD', 9],
  ['Euler a Substep', 7],
  ['DPM++ SDE Substep', 8],
];

function snap(n: number): number {
  const x = Math.round(n / 64) * 64;
  if (x < 256) return 256;
  if (x > 2048) return 2048;
  return x;
}

function supportFits(primary: string, file: string, token: string): boolean {
  const name = file.trim().toLowerCase().split('/').pop() ?? '';
  if (!name) return false;
  const model = familyOf(primary);
  const qwen = name.includes('qwen');
  const clipL = name.includes('clip_l') || name.includes('clip-l');
  const t5 = name.includes('t5');
  const ae = name === 'ae.safetensors';
  const encoder = token.includes('CLIP');
  if (encoder && (name.includes('mmproj') || name.includes('pe_t2i') || name.includes('pe_i2i'))) return false;
  if (encoder && model === 'qwen' && isQwen21(primary) && !qwen3Vl8b(name)) return false;
  if (encoder && (model === 'zImage' || model === 'qwen') && (clipL || t5)) return false;
  if (encoder && (model === 'flux' || model === 'kontext') && qwen) return false;
  if (token.includes('VAE') && model === 'qwen' && ae && !qwen) return false;
  if (token.includes('VAE') && (model === 'flux' || model === 'kontext') && qwen) return false;
  return true;
}

function supportScore(primary: string, file: string, token: string): number {
  if (!supportFits(primary, file, token)) return -1;
  const base = file.trim().toLowerCase().split('/').pop() ?? '';
  const model = familyOf(primary);
  let score = 10;
  if (token.includes('CLIP1')) {
    if (base.includes('clip_l') || base.includes('clip-l')) score = 100;
    if (base.includes('t5')) score = 30;
  } else if (token.includes('CLIP2')) {
    if (base.includes('t5')) score = 100;
    if (base.includes('clip_l') || base.includes('clip-l')) score = 30;
  } else if (token.includes('CLIP')) {
    if (model === 'zImage' && (base.includes('qwen_3_4b') || base.includes('qwen3_4b'))) score = 100;
    else if (model === 'qwen' && isQwen21(primary) && qwen3Vl8b(base)) score = 100;
    else if (model === 'qwen' && !isQwen21(primary) && (base.includes('qwen_2.5_vl') || base.includes('qwen2.5_vl'))) score = 100;
    else if (model === 'zImage' && base.includes('qwen')) score = 80;
    else if (model === 'qwen' && !isQwen21(primary) && base.includes('qwen')) score = 80;
  } else if (token.includes('VAE')) {
    if (model === 'qwen' && isQwen21(primary) && (base.includes('2.1') || base.includes('2_1'))) score = 100;
    else if (model === 'qwen' && base.includes('qwen') && base.includes('vae')) score = isQwen21(primary) ? 40 : 100;
    else if ((model === 'zImage' || model === 'flux' || model === 'kontext') && base === 'ae.safetensors') score = 100;
  }
  return score;
}

/** Fills empty or unfit encoder and VAE slots. Keys are `workflow/token`. */
export function supportFills(
  workflowId: string,
  primary: string,
  choices: Record<string, string>,
  clips: string[],
  vaes: string[],
): Record<string, string> {
  const tokens = workflowId === 'flux' || workflowId === 'flux_kontext'
    ? ['%MODEL_CLIP1%', '%MODEL_CLIP2%', '%MODEL_VAE%']
    : workflowId === 'sd' || workflowId === '__uploaded__'
      ? []
      : ['%MODEL_CLIP%', '%MODEL_VAE%'];
  const out: Record<string, string> = {};
  for (const token of tokens) {
    const current = (choices[`${workflowId}/${token}`] ?? '').trim();
    if (current && supportFits(primary, current, token)) continue;
    const pool = token.includes('VAE') ? vaes : clips;
    let best = '';
    let bestScore = -1;
    for (const file of pool) {
      const score = supportScore(primary, file, token);
      if (score > bestScore) {
        bestScore = score;
        best = file;
      }
    }
    if (best) out[`${workflowId}/${token}`] = best;
    else if (current && !supportFits(primary, current, token)) out[`${workflowId}/${token}`] = '';
  }
  return out;
}

interface GraphRow {
  id: string;
  title: string;
  detail: string;
  group: string;
}

function graphDetail(edit: boolean, id: string): string {
  return `${edit ? 'Edit' : 'Text to image'} · ${id}`;
}

const builtInCreate: GraphRow[] = [
  { id: 'sd', title: 'SD / SDXL / Pony', detail: graphDetail(false, 'sd'), group: 'Text to image graphs' },
  { id: 'flux', title: 'Flux', detail: graphDetail(false, 'flux'), group: 'Text to image graphs' },
  { id: 'qwen_image', title: 'Qwen-Image', detail: graphDetail(false, 'qwen_image'), group: 'Text to image graphs' },
  { id: 'qwen_image_21', title: 'Qwen-Image 2.1', detail: graphDetail(false, 'qwen_image_21'), group: 'Text to image graphs' },
  { id: 'z_image_turbo', title: 'Z-Image Turbo', detail: graphDetail(false, 'z_image_turbo'), group: 'Text to image graphs' },
];

const builtInEdit: GraphRow[] = [
  { id: 'qwen_image_edit', title: 'Qwen-Image-Edit', detail: graphDetail(true, 'qwen_image_edit'), group: 'Edit graphs' },
  { id: 'flux_kontext', title: 'Flux Kontext', detail: graphDetail(true, 'flux_kontext'), group: 'Edit graphs' },
];

const bundledGraphIds = new Set([
  'sd',
  'flux',
  'qwen_image',
  'qwen_image_21',
  'z_image_turbo',
  'qwen_image_edit',
  'flux_kontext',
]);

function stemNamesArchitecture(stem: string): boolean {
  const s = stem.toLowerCase();
  if (s.endsWith('.gguf')) return true;
  if (s.includes('kontext') || s.includes('qwen') || s.includes('flux') || s.includes('pony')) return true;
  if (/z[ _-]?image/.test(s)) return true;
  if (/sd[ _-]?xl|xl(?![a-z])|illustrious|noobai|animagine/.test(s)) return true;
  if (/sd[ _-]?3|stable[ _-]?diffusion[ _-]?3/.test(s)) return true;
  if (/sd[ _-]?1\.?5|(^|[^0-9])1\.5([^0-9]|$)/.test(s)) return true;
  return false;
}

function graphFitsModel(row: GraphRow, edit: boolean, modelFile: string): boolean {
  const file = modelFile.trim();
  if (!file) return true;
  if (row.group === 'Saved on this Comfy' || row.group === 'Could not read') return true;
  if (row.id === '__uploaded__') return true;
  const allowed = workflowForFile(edit, file);
  if (row.id === allowed) return true;
  if (bundledGraphIds.has(row.id)) return false;
  const stem = `${row.title} ${row.id.split(':').pop() ?? ''}`.trim();
  if (!stemNamesArchitecture(stem)) return true;
  return workflowForFile(edit, stem) === allowed;
}

function graphsForModel(rows: GraphRow[], edit: boolean, modelFile: string): GraphRow[] {
  return rows.filter((row) => graphFitsModel(row, edit, modelFile));
}

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

  const [base, setBase] = useState('');
  const [baseQuery, setBaseQuery] = useState('');
  const [installedOnly, setInstalledOnly] = useState(false);
  const [installedKnown, setInstalledKnown] = useState(false);
  const [installedBases, setInstalledBases] = useState<string[]>([]);
  const [installedModels, setInstalledModels] = useState<string[]>([]);
  const [installedLoras, setInstalledLoras] = useState<string[]>([]);
  const [downloading, setDownloading] = useState('');
  const [token, setToken] = useState('');
  const [keySaved, setKeySaved] = useState(false);
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

  const [reachable, setReachable] = useState(false);
  const [diffusionCount, setDiffusionCount] = useState(0);
  const [loraCount, setLoraCount] = useState(0);
  const [pendingGraph, setPendingGraph] = useState<{ json: string; name: string; stance: string } | null>(null);
  const [slotToken, setSlotToken] = useState('');
  const [loraFacts, setLoraFacts] = useState<Record<string, { family: string; meta?: boolean }>>({});
  const rememberFacts = (rows?: { file?: string; family?: string; meta?: boolean }[]) => {
    if (!rows || rows.length === 0) return;
    setLoraFacts((prev) => {
      const next = { ...prev };
      for (const row of rows) {
        const name = row.file?.trim();
        if (!name) continue;
        next[name] = { family: row.family || 'unknown', meta: row.meta === true };
      }
      return next;
    });
  };
  const [uploadedName, setUploadedName] = useState('');
  const [uploadedNodes, setUploadedNodes] = useState(0);
  const [savedTick, setSavedTick] = useState(0);
  const commit = (patch: Record<string, unknown>) => {
    void Promise.resolve(props.onSave(patch)).finally(() => {
      setSavedTick((n) => n + 1);
    });
  };
  const commitComfyModel = (workflowId: string, filename: string, tokenName: string, edit: boolean) => {
    const prior = edit ? props.editModelChoices : props.modelChoices;
    const choices = { ...(prior ?? {}), [`${workflowId}/${tokenName}`]: filename };
    const apply = (next: Record<string, string>) => {
      if (edit) commit({ comfyEditWorkflowId: workflowId, comfyEditModelChoices: next });
      else commit({ comfyCreateWorkflowId: workflowId, comfyCreateModelChoices: next });
    };
    apply(choices);
    if (props.backend !== 'comfyui') return;
    void api.get<{ textEncoders?: string[]; vaes?: string[] }>('/api/image/comfy-catalog').then((cat) => {
      const fills = supportFills(workflowId, filename, choices, cat.textEncoders ?? [], cat.vaes ?? []);
      if (Object.keys(fills).length === 0) return;
      apply({ ...choices, ...fills });
    }).catch(() => {});
  };
  useEffect(() => {
    let live = true;
    void api.get<{ ready?: boolean; kind?: string; blockedLora?: string | null; primary?: string; loraFamily?: string; loraFacts?: { file?: string; family?: string; meta?: boolean }[]; reachable?: boolean; diffusionCount?: number; loraCount?: number; neighborUrl?: string; savedUrl?: string; uploadedTitle?: string; uploadedNodes?: number }>('/api/image/studio/ready?mode=create').then((body) => {
      if (!live) return;
      rememberFacts(body.loraFacts);
      setServerReady(body.ready === true);
      setReachable(body.reachable === true);
      setDiffusionCount(body.diffusionCount ?? 0);
      setLoraCount(body.loraCount ?? 0);
      if (body.uploadedTitle) setUploadedName(body.uploadedTitle);
      if (typeof body.uploadedNodes === 'number') setUploadedNodes(body.uploadedNodes);
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
  useEffect(() => {
    if (props.backend !== 'comfyui' || !file || activeWorkflow === '__uploaded__') return;
    const wanted = workflowForFile(mode === 'edit', file);
    if (wanted === activeWorkflow) return;
    const token = file.toLowerCase().endsWith('.gguf') || wanted !== 'sd'
      ? '%MODEL_DIFFUSION%'
      : '%MODEL_CHECKPOINT%';
    commitComfyModel(wanted, file, token, mode === 'edit');
  }, [props.backend, file, activeWorkflow, mode]);

  const search = (kind: string, tokenName = '') => {
    setSlotToken(tokenName);
    setSheet(kind);
    setQuery('');
    setNote('');
    setRows([]);
    if (kind === 'Graph search') {
      openGraphs();
      return;
    }
    if (kind === 'Model search' || kind === 'LoRA search') {
      if (props.backend === 'drawthings') {
        const catalogUrl = kind === 'LoRA search' && file
          ? `/api/image/local-catalog?model=${encodeURIComponent(file)}`
          : '/api/image/local-catalog';
        void api.get<{ models?: string[]; loras?: string[]; loraFacts?: { file?: string; family?: string; meta?: boolean }[] }>(catalogUrl)
          .then((cat) => {
            rememberFacts(cat.loraFacts);
            setHits(kind === 'LoRA search' ? (cat.loras ?? []) : (cat.models ?? []));
          })
          .catch(() => setHits([]));
        return;
      }
      if (props.backend !== 'comfyui') {
        setHits([]);
        return;
      }
      void api.get<{ deskDiscovery?: string[]; loras?: string[]; textEncoders?: string[]; vaes?: string[]; loraFacts?: { file?: string; family?: string; meta?: boolean }[] }>('/api/image/comfy-catalog')
        .then((cat) => {
          rememberFacts(cat.loraFacts);
          if (kind === 'LoRA search') {
            setHits(cat.loras ?? []);
            return;
          }
          const pool = tokenName.includes('VAE')
            ? (cat.vaes?.length ? cat.vaes : cat.deskDiscovery ?? [])
            : tokenName.includes('CLIP')
              ? (cat.textEncoders?.length ? cat.textEncoders : cat.deskDiscovery ?? [])
              : (cat.deskDiscovery ?? []);
          setHits(tokenName ? pool.filter((name) => supportFits(file, name, tokenName)) : pool);
        })
        .catch(() => setHits([]));
      return;
    }
    setHits([]);
    if (kind === 'Get a model' || kind === 'Get a LoRA') {
      void api.get<{ saved?: boolean; red?: boolean }>('/api/image/civitai/credential').then((body) => {
        setKeySaved(body.saved === true);
      }).catch(() => {
        setNote('Could not read the saved CivitAI key.');
      });
      setInstalledKnown(false);
      void api.get<{ bases?: string[]; models?: string[]; loras?: string[] }>(
        `/api/image/civitai/installed?backend=${encodeURIComponent(props.backend)}`,
      ).then((body) => {
        setInstalledBases(body.bases ?? []);
        setInstalledModels(body.models ?? []);
        setInstalledLoras(body.loras ?? []);
        setInstalledKnown(true);
      }).catch(() => {
        setInstalledBases([]);
        setInstalledModels([]);
        setInstalledLoras([]);
        setInstalledKnown(true);
      });
    }
    const q = query.trim();
    if (!q) return;
    const sheetKind = kind === 'Get a LoRA' ? 'lora' : 'model';
    const runSearch = async () => {
      if (token.trim()) {
        try {
          await api.post('/api/image/civitai/credential', { token: token.trim() });
          setKeySaved(true);
        } catch {
          setNote('Could not save the API key.');
          return;
        }
      }
      try {
        const shown = filterCivitaiBases(
          civitaiBaseGroups,
          baseQuery,
          installedOnly ? installedBases : null,
        );
        const baseSent = visibleCivitaiBase(base, shown);
        const body = await api.get<{ items?: { filename?: string; versionId?: number; type?: string; adult?: boolean; name?: string; downloads?: number; previewUrl?: string; description?: string }[]; needsCredential?: boolean }>(
          `/api/image/civitai/search?q=${encodeURIComponent(q)}&adult=${adult ? 'true' : 'false'}&sheet=${sheetKind}&base=${encodeURIComponent(baseSent)}`,
        );
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
        if (parsed.length === 0) setNote('CivitAI returned no models for that search.');
      } catch (error: unknown) {
        setHits([]);
        setRows([]);
        const message = civitaiFailureNote(error);
        setNote(message === 'CivitAI download failed.' ? 'CivitAI search failed.' : message);
      }
    };
    void runSearch();
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
        const id = choice.workflowId || workflowForFile(mode === 'edit', filename);
        commitComfyModel(id, filename, choice.token, mode === 'edit');
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
      setDownloading(row.filename);
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
        .catch((error: unknown) => setNote(civitaiFailureNote(error)))
        .finally(() => setDownloading(''));
      return;
    }
    if (props.backend === 'comfyui' && sheet === 'Model search' && slotToken) {
      const prior = mode === 'edit' ? props.editModelChoices : props.modelChoices;
      const choices = { ...(prior ?? {}), [`${activeWorkflow}/${slotToken}`]: name };
      if (mode === 'edit') {
        commit({ comfyEditWorkflowId: activeWorkflow, comfyEditModelChoices: choices });
      } else {
        commit({ comfyCreateWorkflowId: activeWorkflow, comfyCreateModelChoices: choices });
      }
      setSlotToken('');
    } else if (props.backend === 'comfyui') {
      const token = name.toLowerCase().endsWith('.gguf') || activeWorkflow !== 'sd'
        ? '%MODEL_DIFFUSION%'
        : '%MODEL_CHECKPOINT%';
      const id = workflowForFile(mode === 'edit', name);
      commitComfyModel(id, name, token, mode === 'edit');
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
    const edit = mode === 'edit';
    const built = graphsForModel(edit ? builtInEdit : builtInCreate, edit, file);
    if (props.backend !== 'comfyui') {
      setGraphs(built);
      setGraphNote('These graphs are built into Front Porch. Connect ComfyUI to also list that install’s templates and saved workflows.');
      return;
    }
    setGraphs(built);
    setGraphNote('Reading this Comfy’s templates…');
    void api.get<{ graphs?: GraphRow[]; editGraphs?: GraphRow[] }>('/api/image/comfy-catalog').then((cat) => {
      const live = edit ? cat.editGraphs : cat.graphs;
      if (!live || live.length === 0) {
        setGraphs(built);
        setGraphNote('Comfy’s template list could not be read. The names below are built into Front Porch.');
        return;
      }
      setGraphs(graphsForModel(live, edit, file));
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
      const stance = graphStance(json);
      const current = mode === 'edit' ? 'edit' : 'create';
      if (stance !== current) {
        setPendingGraph({ json, name: file.name, stance });
        return;
      }
      const nodes = workflowNodeCount(json);
      setUploadedName(file.name);
      setUploadedNodes(nodes);
      if (mode === 'edit') {
        commit({
          comfyEditWorkflowId: '__uploaded__',
          comfyEditUploadedWorkflow: json,
          comfyEditUploadedTitle: file.name,
        });
      } else {
        commit({
          comfyCreateWorkflowId: '__uploaded__',
          comfyCreateUploadedWorkflow: json,
          comfyCreateUploadedTitle: file.name,
        });
      }
      setNote(`${file.name} is the workflow for this ${mode === 'edit' ? 'edit' : 'portrait'}.`);
      setSheet(null);
    });
  };
  const usePendingGraph = (forEdit: boolean) => {
    if (!pendingGraph) return;
    const nodes = workflowNodeCount(pendingGraph.json);
    setUploadedName(pendingGraph.name);
    setUploadedNodes(nodes);
    if (forEdit) {
      commit({
        comfyEditWorkflowId: '__uploaded__',
        comfyEditUploadedWorkflow: pendingGraph.json,
        comfyEditUploadedTitle: pendingGraph.name,
      });
    } else {
      commit({
        comfyCreateWorkflowId: '__uploaded__',
        comfyCreateUploadedWorkflow: pendingGraph.json,
        comfyCreateUploadedTitle: pendingGraph.name,
      });
    }
    setPendingGraph(null);
    setSheet(null);
  };

  const filled = (props.loras ?? []).filter((slot) => slot.file.trim());
  const modelFamily = familyOf(file);
  const certain = overrideFamily === modelFamily
    ? undefined
    : filled.find((slot) => slotBadge(slot.file, file, loraFacts) === 'other base');
  const serverBlocked = !certain && loraBlock != null && overrideFamily !== (loraBlock.family || modelFamily);
  const ready = certain || serverBlocked ? false : serverReady;
  const needsQwen21Encoder = isQwen21(file) && supportRows(activeWorkflow, choices, file)
    .some((row) => row.token.includes('CLIP') && row.file === '');
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
      ? `Workflow · your file · ${uploadedName || 'workflow'} · ${uploadedNodes} nodes`
      : `Workflow · ${mode === 'edit' ? 'Edit' : 'Text to image'} · ${activeWorkflow}`;
  const familyLabel = file ? (modelFamily === 'zImage' ? 'Z-Image' : modelFamily === 'qwen' ? 'Qwen' : modelFamily === 'unknown' ? 'Model' : modelFamily) : 'No model chosen';
  const checkpointOnly = activeWorkflow === 'sd';
  const otherGraphs = graphsForModel(
    mode === 'edit' ? builtInCreate : builtInEdit,
    mode !== 'edit',
    file,
  ).filter((row) => {
    const q = query.trim().toLowerCase();
    return q.length > 0 && (row.title.toLowerCase().includes(q) || row.id.toLowerCase().includes(q));
  });

  return (
    <section className="studio-desk">
      <style>{`
        .fp-civitai-page { position: fixed; inset: 0; z-index: 40; overflow: auto; background: #0F172A; padding: 24px; }
        .fp-pill { border-radius: 999px; border: 1px solid #F4A259; background: transparent; color: #F4A259; padding: 6px 14px; margin: 0 8px 8px 0; font-weight: 600; }
        .fp-pill[aria-pressed="true"] { background: #F4A259; color: #1A1200; }
        .fp-desk-body { display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(0, 0.85fr); column-gap: 16px; align-items: start; }
        .fp-desk-rail { grid-column: 1; grid-row: 1; min-width: 0; }
        .fp-desk-output { grid-column: 1; grid-row: 2; min-width: 0; }
        .fp-desk-output img { max-width: 100%; max-height: 420px; object-fit: contain; }
        .fp-desk-stove { grid-column: 2; grid-row: 1 / span 2; min-width: 0; }
        @media (max-width: 720px) {
          .fp-desk-body { display: flex; flex-direction: column; }
          .fp-desk-rail, .fp-desk-stove, .fp-desk-output { grid-column: auto; grid-row: auto; }
          .fp-desk-output { order: 3; }
        }
      `}</style>
      <div className="fp-desk-body">
        <div className="fp-desk-rail" data-region="rail">
          <div>Subject</div>
          <button type="button" className="fp-pill" aria-pressed={subject === 'free'} onClick={() => setSubject('free')}>Freeform</button>
          <button type="button" className="fp-pill" aria-pressed={subject === 'char'} onClick={() => setSubject('char')}>Character</button>
          <button type="button" className="fp-pill" aria-pressed={subject === 'persona'} onClick={() => setSubject('persona')}>Your persona</button>
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
        {props.result ? (
          <div className="fp-desk-output" data-region="output">{props.result}</div>
        ) : null}
        <div className="fp-desk-stove" data-region="stove">
          <div>Connection</div>
          <div>{backendName}</div>
          <div>{url}</div>
          {props.backend === 'remote' ? null : reachable ? (
            props.backend === 'comfyui' || props.backend === 'drawthings' ? (
              <p>{`Reachable · ${diffusionCount} diffusion files · ${loraCount} LoRAs`}</p>
            ) : (
              <p>Reachable</p>
            )
          ) : (
            <p>Not running</p>
          )}
          {props.backend === 'remote' ? null : (
            <button type="button" onClick={() => {
              void api.get<{ reachable?: boolean; diffusionCount?: number; loraCount?: number }>('/api/image/studio/ready?mode=create').then((body) => {
                setReachable(body.reachable === true);
                setDiffusionCount(body.diffusionCount ?? 0);
                setLoraCount(body.loraCount ?? 0);
              }).catch(() => setReachable(false));
            }}>Check</button>
          )}
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
          {props.backend === 'comfyui' ? (
            <button type="button" onClick={() => openGraphs()}>Change graph</button>
          ) : null}
          <button type="button" onClick={() => search('Model search')}>Change model</button>
          <button type="button" onClick={() => search('Get a model')}>Get a model from CivitAI</button>
          {props.backend === 'drawthings' ? null : checkpointOnly ? <p>This checkpoint graph has no text encoder or VAE slot.</p> : (
            <>
              <p>This graph also loads</p>
              {supportRows(activeWorkflow, choices, file).map((row) => (
                <div key={row.token}>
                  <span>{row.role}</span>
                  <span>{row.file || 'Not chosen'}</span>
                  <button type="button" onClick={() => search('Model search', row.token)}>Change</button>
                </div>
              ))}
              <p>These files do not set the LoRA family. The text encoder can be Qwen while the model is Z-Image.</p>
            </>
          )}
          <div>LoRA</div>
          {filled.map((slot) => (
            <div key={slot.file}>
              <span>{slot.file}</span>
              <span>{slotBadge(slot.file, file, loraFacts)}</span>
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
          <div>
            {['512×512', '768×768', '1024×1024', '1536×1024', '1024×1536'].map((label) => (
              <button
                key={label}
                type="button"
                className="fp-pill"
                aria-pressed={label === `${width}×${height}`}
                onClick={() => {
                  const [cw, ch] = label.split('×');
                  saveSize(cw, ch);
                }}
              >
                {label}
              </button>
            ))}
          </div>
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
          {advanced && props.backend !== 'drawthings' ? (
            <>
              <label>
                Steps
                <input aria-label="Steps" type="range" min={1} max={50} value={props.steps} onChange={(e) => commit({ steps: Number(e.target.value) })} />
              </label>
              <label>
                CFG
                <input aria-label="CFG" type="range" min={1} max={20} step={0.5} value={cfg} onChange={(e) => commit({ cfgScale: Number(e.target.value) })} />
              </label>
              <label>
                Sampler
                <select aria-label="Sampler" value={props.sampler} onChange={(e) => commit({ sampler: e.target.value })}>
                  {[props.sampler, 'Euler a', 'Euler', 'DPM++ 2M', 'DPM++ 2M Karras', 'DPM++ SDE Karras', 'DPM++ 2M SDE Karras', 'DDIM', 'UniPC', 'LCM'].filter((name, index, all) => name && all.indexOf(name) === index).map((name) => <option key={name}>{name}</option>)}
                </select>
              </label>
              <label>
                Scheduler
                <select aria-label="Scheduler" value={scheduler} onChange={(e) => commit({ scheduler: e.target.value })}>
                  {[scheduler, 'Automatic', 'normal', 'karras', 'exponential', 'sgm_uniform', 'simple', 'beta'].filter((name, index, all) => name && all.indexOf(name) === index).map((name) => <option key={name}>{name}</option>)}
                </select>
              </label>
            </>
          ) : null}
          {advanced && props.backend === 'drawthings' ? (
            <label>
              Sampler
              <select
                aria-label="Draw Things sampler"
                value={String(props.drawThingsSampler ?? 16)}
                onChange={(e) => commit({ drawThingsSampler: Number(e.target.value) })}
              >
                {drawThingsSamplers.map(([label, value]) => (
                  <option key={value} value={value}>{label}</option>
                ))}
              </select>
            </label>
          ) : null}
          <p>{props.busy ? 'Generating…' : ready ? 'Ready to generate.' : certain || serverBlocked ? `Not ready — LoRA architecture does not match ${file}.` : needsQwen21Encoder ? 'Not ready — this model needs the Qwen3-VL 8B text encoder.' : 'Not ready.'}</p>
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
          {pendingGraph?.stance === 'unstated' ? (
            <div>
              <p>This graph doesn’t say Create or Edit.</p>
              <button type="button" onClick={() => usePendingGraph(false)}>Use for Create</button>
              <button type="button" onClick={() => usePendingGraph(true)}>Use for Edit</button>
            </div>
          ) : null}
          {pendingGraph && pendingGraph.stance !== 'unstated' && pendingGraph.stance !== (mode === 'edit' ? 'edit' : 'create') ? (
            <button type="button" onClick={() => usePendingGraph(pendingGraph.stance === 'edit')}>
              {pendingGraph.stance === 'edit' ? 'Use it for Edit' : 'Use it for Create'}
            </button>
          ) : null}
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
        <div
          className="fp-civitai-page"
          role="dialog"
          aria-label={sheet === 'Get a LoRA' ? 'Get a LoRA from CivitAI' : 'Get a model from CivitAI'}
        >
          <button type="button" onClick={() => { setSheet(null); setCivitaiDetail(null); }}>Close</button>
          <h2>{civitaiDetail?.name || (sheet === 'Get a LoRA' ? 'Get a LoRA from CivitAI' : 'Get a model from CivitAI')}</h2>
          <label>
            <input type="checkbox" checked={adult} onChange={(e) => setAdult(e.target.checked)} />
            Include adult models from civitai.red
          </label>
          {keySaved && token.trim() === '' ? (
            <p>
              API key saved. Search and adult results on civitai.red use this key.
              <button type="button" onClick={() => setKeySaved(false)}>Replace</button>
            </p>
          ) : (
            <label>
              API key
              <input type="password" autoComplete="off" value={token} onChange={(e) => setToken(e.target.value)} onBlur={saveKey} />
            </label>
          )}
          <label>
            Filter bases
            <input
              aria-label="Filter bases"
              placeholder="Qwen, Flux, SDXL"
              value={baseQuery}
              onChange={(e) => {
                const next = e.target.value;
                setBaseQuery(next);
                setBase((current) => visibleCivitaiBase(
                  current,
                  filterCivitaiBases(civitaiBaseGroups, next, installedOnly ? installedBases : null),
                ));
              }}
            />
          </label>
          <label>
            <input
              type="checkbox"
              checked={installedOnly}
              onChange={(e) => {
                const next = e.target.checked;
                setInstalledOnly(next);
                setBase((current) => visibleCivitaiBase(
                  current,
                  filterCivitaiBases(civitaiBaseGroups, baseQuery, next ? installedBases : null),
                ));
              }}
            />
            Only installed models
          </label>
          {installedOnly && !installedKnown ? <p>Looking through the models folder…</p> : null}
          <label>
            Base model
            <select
              aria-label="Base model"
              value={visibleCivitaiBase(base, filterCivitaiBases(civitaiBaseGroups, baseQuery, installedOnly ? installedBases : null))}
              onChange={(e) => setBase(e.target.value)}
            >
              <option value="">Any base</option>
              {filterCivitaiBases(civitaiBaseGroups, baseQuery, installedOnly ? installedBases : null).map((group) => (
                <optgroup key={group.title} label={group.title}>
                  {group.choices.map((choice) => (
                    <option key={choice.api} value={choice.api}>{choice.label}</option>
                  ))}
                </optgroup>
              ))}
            </select>
          </label>
          {installedOnly && installedKnown && filterCivitaiBases(civitaiBaseGroups, baseQuery, installedBases).length === 0 ? (
            <p>No installed model matches a CivitAI base.</p>
          ) : null}
          <input aria-label="Search" placeholder={sheet === 'Get a LoRA' ? 'Clothes' : 'Search CivitAI'} value={query} onChange={(e) => setQuery(e.target.value)} />
          <button type="button" onClick={() => search(sheet)}>Search</button>
          {downloading ? <progress aria-label="Download progress" /> : null}
          {civitaiDetail ? (
            <div>
              {civitaiDetail.preview ? (
                <img alt="" src={civitaiDetail.preview} style={{ width: '100%', objectFit: 'contain', maxHeight: '70vh' }} />
              ) : null}
              <p>{(civitaiDetail.downloads ?? 0).toLocaleString()} downloads</p>
              <p>{civitaiDetail.description || 'CivitAI did not send a description.'}</p>
              <button type="button" onClick={() => setCivitaiDetail(null)}>Back</button>
              <button type="button" onClick={() => {
                const pool = sheet === 'Get a LoRA' ? installedLoras : installedModels;
                const have = pool.some((name) => name.toLowerCase() === civitaiDetail.filename.toLowerCase());
                if (have) void selectInstalled(civitaiDetail.filename, sheet === 'Get a LoRA');
                else saveInstalled(civitaiDetail.filename);
              }}>{(sheet === 'Get a LoRA' ? installedLoras : installedModels).some((name) => name.toLowerCase() === civitaiDetail.filename.toLowerCase()) ? 'Installed' : 'Download'}</button>
            </div>
          ) : sheet === 'Get a LoRA' ? (
            rows.map((row) => {
              const have = installedLoras.some((name) => name.toLowerCase() === row.filename.toLowerCase());
              return (
                <div key={row.filename} style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '8px 0' }}>
                  <button
                    type="button"
                    onClick={() => setCivitaiDetail(row)}
                    style={{ display: 'flex', gap: 8, textAlign: 'left' }}
                  >
                    {row.preview ? <img alt="" src={row.preview} width={88} height={88} style={{ objectFit: 'cover' }} /> : null}
                    <span>
                      <strong>{row.name || row.filename}</strong>
                      <span>{(row.downloads ?? 0).toLocaleString()} downloads</span>
                    </span>
                  </button>
                  <button
                    type="button"
                    onClick={() => (have ? void selectInstalled(row.filename, true) : saveInstalled(row.filename))}
                  >
                    {have ? 'Installed' : row.filename}
                  </button>
                </div>
              );
            })
          ) : (
            <ul>
              {hits.map((item) => {
                const have = installedModels.some((name) => name.toLowerCase() === item.toLowerCase());
                return (
                  <li key={item}>
                    <button type="button" onClick={() => (have ? void selectInstalled(item, false) : saveInstalled(item))}>
                      {have ? 'Installed' : item}
                    </button>
                  </li>
                );
              })}
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
          <p>These are the LoRA files the connected app listed. A tap fills the first empty slot.</p>
          <p>Matches this model</p>
          <ul>
            {hits.filter((item) => slotBadge(item, file, loraFacts) !== 'other base').map((item) => (
              <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
            ))}
          </ul>
          <p>Other bases</p>
          <ul>
            {hits.filter((item) => slotBadge(item, file, loraFacts) === 'other base').map((item) => (
              <li key={item}><button type="button" onClick={() => saveInstalled(item)}>{item}</button></li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
