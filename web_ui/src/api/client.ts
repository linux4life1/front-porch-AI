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
    const payload = (typeof data === 'object' && data !== null ? data : {}) as Record<
      string,
      unknown
    >;
    const message = (payload.error as string) || `Request failed (${res.status})`;
    throw new ApiError(res.status, message, payload);
  }
  return data as T;
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(path, {
    method,
    credentials: 'include',
    headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
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
      const text = await res.text();
      throw new ApiError(res.status, text || `Request failed (${res.status})`, {});
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
      const text = await res.text();
      throw new ApiError(res.status, text || `Request failed (${res.status})`, {});
    }
    return res.blob();
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
};
