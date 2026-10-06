// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Thin fetch wrapper for the rewritten Dart web server API. The session lives
// in an HttpOnly cookie, so every request sends credentials; we never handle a
// token in JS.

export class ApiError extends Error {
  status: number;
  payload: Record<string, unknown>;
  constructor(status: number, message: string, payload: Record<string, unknown>) {
    super(message);
    this.status = status;
    this.payload = payload;
  }
}

/** Parse a failed JSON `{ error }` body. Used by JSON and blob downloads. */
export function parseApiErrorBody(text: string, status: number): ApiError {
  try {
    const data = JSON.parse(text) as unknown;
    const payload =
      typeof data === 'object' && data !== null
        ? (data as Record<string, unknown>)
        : {};
    const message =
      typeof payload.error === 'string' && payload.error.length > 0
        ? payload.error
        : `Request failed (${status})`;
    return new ApiError(status, message, payload);
  } catch {
    return new ApiError(status, text || `Request failed (${status})`, {});
  }
}

async function handle<T>(res: Response): Promise<T> {
  const text = await res.text();
  let data: unknown = undefined;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }
  if (!res.ok) {
    throw parseApiErrorBody(text, res.status);
  }
  return data as T;
}

// Reads (GET) are never legitimately long, but they hang forever when the
// desktop's engine is busy — which read as a frozen app on the iPad. Bound
// them at 30s so a stall surfaces as an ApiError instead of dead air. POSTs
// stay unbounded on purpose: several (journal regen, objective task-gen,
// growth pass) legitimately await minutes of local-LLM work.
const READ_TIMEOUT_MS = 30_000;

function readSignal(): AbortSignal | undefined {
  return typeof AbortSignal !== 'undefined' && 'timeout' in AbortSignal
    ? AbortSignal.timeout(READ_TIMEOUT_MS)
    : undefined;
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: 'include',
    headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    signal: method === 'GET' ? readSignal() : undefined,
  });
  return handle<T>(res);
}

export const api = {
  get: <T>(path: string) => request<T>('GET', path),
  post: <T>(path: string, body?: unknown) => request<T>('POST', path, body),
  /** Upload a raw binary file (character-card import). Filename rides as a query
   *  param; the body is the raw bytes. */
  upload: async <T>(path: string, file: File): Promise<T> => {
    const sep = path.includes('?') ? '&' : '?';
    const res = await fetch(`${path}${sep}filename=${encodeURIComponent(file.name)}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/octet-stream' },
      body: file,
    });
    return handle<T>(res);
  },
  /** GET a binary response body (ebook / audiobook download). */
  getForBlob: async (path: string): Promise<Blob> => {
    const res = await fetch(path, { method: 'GET', credentials: 'include' });
    if (!res.ok) {
      throw parseApiErrorBody(await res.text(), res.status);
    }
    return res.blob();
  },
  /** POST JSON and get the response body as audio/binary (TTS synthesis). */
  postForBlob: async (path: string, body?: unknown): Promise<Blob> => {
    const res = await fetch(path, {
      method: 'POST',
      credentials: 'include',
      headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) {
      throw parseApiErrorBody(await res.text(), res.status);
    }
    return res.blob();
  },
  /** POST JSON and get a file back, named by the server's
   *  `Content-Disposition: attachment; filename*=UTF-8''…` (.porch export). */
  postForFile: async (
    path: string,
    body: unknown,
    fallbackName: string,
  ): Promise<{ blob: Blob; fileName: string }> => {
    const res = await fetch(path, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      throw parseApiErrorBody(await res.text(), res.status);
    }
    const named = /filename\*=UTF-8''([^;]+)/i.exec(res.headers.get('Content-Disposition') ?? '');
    return { blob: await res.blob(), fileName: named ? decodeURIComponent(named[1]) : fallbackName };
  },
  /** POST a raw recording blob and get JSON back (STT transcription). The
   *  container extension rides as a query param so the server names the temp
   *  file Whisper reads. */
  postBlob: async <T>(path: string, blob: Blob, ext: string): Promise<T> => {
    const sep = path.includes('?') ? '&' : '?';
    const res = await fetch(`${path}${sep}ext=${encodeURIComponent(ext)}`, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': blob.type || 'application/octet-stream' },
      body: blob,
    });
    return handle<T>(res);
  },
  /** Absolute URL for an asset/image endpoint (cookie auth applies). */
  url: (path: string) => path,
  /** Build a cache-friendly avatar thumbnail URL: a display [w]idth plus an
   *  optional content [v]ersion. Where the picture is mutable (a character's
   *  primary avatar) [v] is the file's modified-time, so swapping the picture
   *  yields a new URL — letting the service worker cache thumbnails as
   *  effectively immutable and reload them only when they actually change. */
  avatarUrl: (path: string, w: number, v?: number) =>
    `${path}?w=${w}${v ? `&v=${v}` : ''}`,
};
