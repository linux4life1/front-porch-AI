// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The few rules the phone desk keeps for itself. Choosing a model, a graph or
// a slot, and what counts as ready, are the server's.

import type { LoraFact } from './types';

/** Nearest multiple of 64, each side within 256 to 2048 (as the server). */
export function snapSize(n: number): number {
  const x = Math.round(n / 64) * 64;
  if (x < 256) return 256;
  if (x > 2048) return 2048;
  return x;
}

export function sizeParts(size: string): [string, string] {
  const [w = '', h = ''] = size.split(/[x×]/);
  return [w.trim(), h.trim()];
}

const FAMILY_LABELS: Record<string, string> = {
  sd15: 'SD 1.5',
  sdxl: 'SDXL',
  pony: 'Pony',
  sd3: 'SD 3',
  flux: 'Flux',
  qwen: 'Qwen',
  zImage: 'Z-Image',
  kontext: 'Flux Kontext',
};

/** The words for the model family the server reports. */
export function familyLabel(family: string | undefined, file: string): string {
  if (!file) return 'No model chosen';
  return (family && FAMILY_LABELS[family]) || 'Model';
}

/** How a LoRA sits with the model: `match`, `likely` (nothing certain says
 *  otherwise) or `other base` (the file's own metadata says another base). */
export function loraBadge(
  file: string,
  modelFamily: string | undefined,
  facts: Record<string, LoraFact>,
): 'match' | 'likely' | 'other base' {
  const fact = facts[file];
  const family = fact?.family ?? 'unknown';
  if (family !== 'unknown' && family === modelFamily) return 'match';
  const pony =
    (family === 'pony' && modelFamily === 'sdxl') ||
    (family === 'sdxl' && modelFamily === 'pony');
  if (family === 'unknown' || !modelFamily || modelFamily === 'unknown' || pony || !fact?.meta) {
    return 'likely';
  }
  return 'other base';
}

/** Facts by file name, later ones winning. */
export function factsByFile(...lists: (LoraFact[] | undefined)[]): Record<string, LoraFact> {
  const out: Record<string, LoraFact> = {};
  for (const list of lists) {
    for (const row of list ?? []) {
      const name = row.file?.trim();
      if (name) out[name] = { family: row.family || 'unknown', meta: row.meta === true };
    }
  }
  return out;
}

/** True for a filename the desk would show as a graph file the person chose. */
export function graphMatches(row: { title: string; detail: string }, query: string): boolean {
  const q = query.trim().toLowerCase();
  return !q || row.title.toLowerCase().includes(q) || row.detail.toLowerCase().includes(q);
}

/** The Ready line for the verdict the server gave. */
export function readyLine(opts: {
  ready: boolean;
  busy: boolean;
  kind?: string;
  message?: string;
  missingClass?: string;
  backendName: string;
  file: string;
  blockedLora?: string | null;
}): string {
  if (opts.busy) return 'Generating…';
  if (opts.ready) return 'Ready to generate.';
  switch (opts.kind) {
    case 'loraMismatch':
      return `Not ready — LoRA architecture does not match ${opts.file}.`;
    case 'unreachable':
      return `Not ready — ${opts.backendName} is not running.`;
    case 'missingFile':
      return 'Not ready — choose the model files this graph loads.';
    case 'missingNodeClass':
      return `Not ready — ComfyUI is missing the ${opts.missingClass ?? 'a required'} node.`;
    case 'needsUnetGraph':
      return 'Not ready — this model needs a graph that loads a diffusion model.';
    case 'needsLoaderUpdate':
    case 'needsComfyRestart':
      return opts.message ? `Not ready — ${opts.message}` : 'Not ready.';
    default:
      return 'Not ready.';
  }
}
