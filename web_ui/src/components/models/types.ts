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
