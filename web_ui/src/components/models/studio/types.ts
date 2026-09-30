// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the phone Image Studio desk reads from /api/image/*.

import type { ImageRemoteHost } from '../imageRemote';

export type Mode = 'create' | 'edit';

export interface LoraSlot {
  file: string;
  weight: number;
}

export interface LoraFact {
  file?: string;
  family?: string;
  meta?: boolean;
}

/** One row of Change graph. */
export interface GraphRow {
  id: string;
  title: string;
  detail: string;
  group: string;
}

/** GET /api/image/config. */
export interface ImageConfig {
  backend: string;
  isConfigured: boolean;
  isGenerating?: boolean;
  statusMessage?: string;
  genProgress?: number | null;
  adultAllowed?: boolean;
  size: string;
  style: string;
  model: string;
  editModel?: string;
  negativePrompt: string;
  steps: number;
  cfgScale: number;
  sampler: string;
  scheduler: string;
  drawThingsSampler?: number;
  drawThingsSamplers?: { label: string; value: number }[];
  lora?: string;
  loraWeight?: number;
  loras?: LoraSlot[];
  localUrl: string;
  comfyUrl: string;
  promptReview: boolean;
  drawThingsHost: string;
  drawThingsPort: number;
  remoteApiUrl: string;
  remoteModelName?: string;
  hasApiKey: boolean;
  imageRemoteHost?: string;
  imageRemoteHosts?: ImageRemoteHost[];
  comfyCreateWorkflowId?: string;
  comfyCreateModelChoices?: Record<string, string>;
  comfyCreateUploadedTitle?: string;
  comfyEditWorkflowId?: string;
  comfyEditModelChoices?: Record<string, string>;
  comfyEditUploadedTitle?: string;
}

/** GET /api/image/studio/ready?mode=. */
export interface ReadyFacts {
  ready?: boolean;
  kind?: string;
  message?: string;
  missingClass?: string;
  primary?: string;
  blockedLora?: string | null;
  loraFamily?: string;
  loraFacts?: LoraFact[];
  reachable?: boolean;
  diffusionCount?: number;
  loraCount?: number;
  mode?: Mode;
  workflowId?: string;
  canUpdateLoader?: boolean;
  slots?: { token: string; label: string; file: string }[];
  uploadedTitle?: string;
  uploadedNodes?: number;
}

/** GET /api/image/comfy-catalog. */
export interface Catalog {
  deskDiscovery?: string[];
  loras?: string[];
  textEncoders?: string[];
  vaes?: string[];
  loraFacts?: LoraFact[];
  graphs?: GraphRow[];
  editGraphs?: GraphRow[];
  slotFiles?: { files: string[]; unfit: string[] };
}

/** POST /api/image/studio/graph. */
export interface GraphUpload {
  stored: boolean;
  stance: 'create' | 'edit' | 'unstated';
  nodes?: number;
  mode?: Mode;
  title?: string;
  config?: ImageConfig;
}

/** A CivitAI download the desktop is running. */
export interface CivitaiJob {
  jobId: string;
  name: string;
  state: 'running' | 'done' | 'failed' | 'cancelled';
  received: number;
  total: number;
  percent: number;
  code?: string;
  error?: string;
}
