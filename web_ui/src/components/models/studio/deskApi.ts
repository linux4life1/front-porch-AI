// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone desk's calls. The choosing rules live on the server; these only
// say what the person chose.

import { api } from '../../../api/client';
import type { Catalog, GraphUpload, ImageConfig, Mode, ReadyFacts } from './types';

export const fetchReady = (mode: Mode) =>
  api.get<ReadyFacts>(`/api/image/studio/ready?mode=${mode}`);

export function fetchCatalog(
  mode: Mode,
  opts: { token?: string; lora?: boolean } = {},
) {
  const query = new URLSearchParams({ mode });
  if (opts.token) query.set('token', opts.token);
  if (opts.lora) query.set('lora', '1');
  return api.get<Catalog>(`/api/image/comfy-catalog?${query.toString()}`);
}

export const fetchLocalCatalog = (model: string) =>
  api.get<{ models?: string[]; loras?: string[]; loraFacts?: Catalog['loraFacts'] }>(
    model
      ? `/api/image/local-catalog?model=${encodeURIComponent(model)}`
      : '/api/image/local-catalog',
  );

/** Picks the primary model, a graph, or one slot of the graph on the desk. */
export const pick = (body: {
  kind: 'model' | 'graph' | 'support';
  mode: Mode;
  file?: string;
  id?: string;
  token?: string;
}) => api.post<ImageConfig>('/api/image/studio/pick', body);

export const installedChoice = (body: {
  filename: string;
  lora: boolean;
  workflowId: string;
}) =>
  api.post<{
    accept?: boolean;
    kind?: string;
    token?: string;
    workflowId?: string;
    loras?: { file: string; weight: number }[];
  }>('/api/image/studio/installed', body);

export const writePrompt = (subject: string, instruction: string) =>
  api.post<{ prompt: string }>('/api/image/studio/write-prompt', { subject, instruction });

/** base64 of [bytes], in pieces so a big file does not overflow the call. */
export function base64Of(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    out += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(out);
}

/** Sends a graph file (.json, or a PNG Comfy saved) for the server to check
 *  and store. It needs the web password (and a 2FA code when there is one). */
export async function uploadGraph(opts: {
  bytes: Uint8Array;
  name: string;
  mode: Mode;
  useFor?: Mode;
  password: string;
  totpCode?: string;
}): Promise<GraphUpload> {
  const body: Record<string, unknown> = {
    data: base64Of(opts.bytes),
    name: opts.name,
    mode: opts.mode,
    currentPassword: opts.password,
  };
  if (opts.useFor) body.useFor = opts.useFor;
  if (opts.totpCode?.trim()) body.totpCode = opts.totpCode.trim();
  return api.post<GraphUpload>('/api/image/studio/graph', body);
}

/** The most a graph file may weigh; the server checks it too. */
export const MAX_GRAPH_BYTES = 8 * 1024 * 1024;
