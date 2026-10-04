// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared types + formatters for the Models page components (status, local
// models, HuggingFace search/download, hardware).

export interface BackendStatus {
  isLocal: boolean;
  running: boolean;
  starting: boolean;
  modelReady: boolean;
  statusMessage: string;
  loadedModel: string;
  /** Host CPU lacks AVX2 and has no NVIDIA GPU → local AI runs CPU-only, slowly. */
  cpuOnlyLowPerf?: boolean;
  /** Managed KoboldCpp engine acquisition state (first-launch rework —
   *  the binary no longer downloads at boot; it can be missing or mid-fetch). */
  engineInstalled?: boolean;
  engineDownloading?: boolean;
  engineProgress?: number;
  engineStatusMessage?: string;
  engineError?: string;
  /** Remote live ping (additive). Green Ready is remoteReachable, not a saved key. */
  isReady?: boolean;
  remoteConfigured?: boolean;
  remoteReachable?: boolean;
  remoteReachability?: 'unknown' | 'checking' | 'reachable' | 'unreachable';
}

export interface LocalModel {
  name: string;
  path: string;
  sizeBytes: number;
  quant: string;
  paramCountB: number | null;
  loaded: boolean;
}

export interface HFModel {
  id: string;
  name: string;
  author: string;
  likes: number;
  downloads: number;
  description: string | null;
}

export interface HFFile {
  filename: string;
  sizeBytes: number;
  repoId: string;
  quant: string;
}

export interface Download {
  id: string;
  filename: string;
  repoId: string | null;
  state: string; // pending | downloading | paused | completed | failed | verifying | cancelled
  progress: number;
  bytesDownloaded: number;
  totalBytes: number;
  speedBytesPerSec: number;
  etaSeconds: number;
  status: string; // ready-made status line from the backend
  errorMessage: string | null;
}

export interface DownloadsState {
  downloads: Download[];
  overallProgress: number;
  overallSpeed: number;
  activeCount: number;
}

export interface Hardware {
  gpuName: string;
  vramMb: number;
  ramMb: number;
  vendor: string;
  hasCuda: boolean;
  hasRocm: boolean;
  hasMetal: boolean;
  isSharedMemory: boolean;
  detecting: boolean;
  /** False (or absent, on an older app): KoboldCpp fits the model to the card itself. */
  gpuLayersManual?: boolean;
  gpuLayers?: number;
  /** The layer count in use before the move to Automatic, until acknowledged. */
  gpuLayersRetired?: number | null;
}

/** What the Hardware panel says about how the model is placed in graphics memory. */
export function graphicsMemoryLine(hw: Pick<Hardware, 'gpuLayersManual' | 'gpuLayers'>): string {
  return hw.gpuLayersManual
    ? `${hw.gpuLayers ?? 0} layers, set on the computer`
    : 'Automatic (KoboldCpp fits the model)';
}

/** The one-time note about the move to Automatic, or null when there is nothing to say. */
export function retiredLayersNote(hw: Pick<Hardware, 'gpuLayersRetired'>): string | null {
  return typeof hw.gpuLayersRetired === 'number'
    ? `Before this update GPU layers was set to ${hw.gpuLayersRetired}. KoboldCpp now works out the fit by itself, so that number is no longer sent. It is kept: switch on “Set layers myself” on the computer to use it again.`
    : null;
}

export const fmtSize = (b: number): string =>
  b >= 1e9 ? `${(b / 1e9).toFixed(1)} GB` : b >= 1e6 ? `${(b / 1e6).toFixed(0)} MB` : `${(b / 1e3).toFixed(0)} KB`;

export const fmtGb = (mb: number): string => (mb > 0 ? `${(mb / 1024).toFixed(1)} GB` : '—');

export const fmtEta = (s: number): string => {
  if (s <= 0) return '--';
  const m = Math.floor(s / 60);
  const sec = s % 60;
  if (m >= 60) return `${Math.floor(m / 60)}h ${m % 60}m`;
  return `${m}m ${String(sec).padStart(2, '0')}s`;
};
