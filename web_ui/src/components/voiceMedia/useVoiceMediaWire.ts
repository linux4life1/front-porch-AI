// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Voice & Media's live view of the host: one read of
// /api/voice/status on mount and on every reconnect, a re-read on each
// `settings_changed` (a write from the desktop or another tab), and a poll
// while the ONNX model or the photo helper downloads — the same 1.2 s poll the
// model downloader uses (models/ModelDownloads.tsx). A write paints at once
// and rolls back with a message if the host refuses it.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import { ChatSocket } from '../../api/ws';

export interface OnnxModel {
  state: 'ready' | 'downloading' | 'missing';
  progress: number | null;
  failed: boolean;
}

export interface PhotoHelper {
  state: 'installed' | 'downloading' | 'absent';
  progress: number;
  sizeLabel: string;
  captioning: boolean;
}

export interface VoiceVoice {
  id: string;
  name: string;
}

/** GET /api/voice/status. Every key past the first four is additive (7c),
 *  so an older host leaves them undefined and the card that needs one hides. */
export interface VoiceMediaStatus {
  ttsEnabled: boolean;
  ttsEngine?: string;
  sttEnabled?: boolean;
  sttAvailable: boolean;
  globalVoice?: string;
  voices?: VoiceVoice[];
  autoSendTranscription?: boolean;
  imageGenEnabled?: boolean;
  expressionEnabled?: boolean;
  expressionMode?: string;
  expressionDisplay?: string;
  expressionRerollSame?: boolean;
  expressionEmojiBurst?: boolean;
  expressionEmojiBurstSize?: number;
  expressionFallback?: string;
  onnxModel?: OnnxModel | null;
  photoHelper?: PhotoHelper | null;
}

/** The keys POST /api/voice/settings accepts. */
export type VoiceMediaPatch = Partial<
  Pick<
    VoiceMediaStatus,
    | 'ttsEnabled'
    | 'sttEnabled'
    | 'autoSendTranscription'
    | 'imageGenEnabled'
    | 'expressionEnabled'
    | 'expressionMode'
    | 'expressionDisplay'
    | 'expressionRerollSame'
    | 'expressionEmojiBurst'
    | 'expressionEmojiBurstSize'
    | 'expressionFallback'
  >
>;

export interface VoiceMediaWire {
  status: VoiceMediaStatus | null;
  error: string;
  write: (patch: VoiceMediaPatch) => void;
  /** One of the verbs (ONNX download, photo cancel / remove). */
  act: (path: string, failure: string) => void;
}

export const POLL_MS = 1200;

export function useVoiceMediaWire(): VoiceMediaWire {
  const [status, setStatus] = useState<VoiceMediaStatus | null>(null);
  const [error, setError] = useState('');
  // Writes still in flight: a read that lands meanwhile must not undo them.
  const pending = useRef(0);
  const alive = useRef(true);
  const statusRef = useRef(status);
  statusRef.current = status;

  const read = useCallback(() => {
    api
      .get<VoiceMediaStatus>('/api/voice/status')
      .then((s) => {
        if (alive.current && pending.current === 0) setStatus(s);
      })
      .catch((e: unknown) => console.warn('Could not read the Voice & Media settings', e));
  }, []);

  useEffect(() => {
    alive.current = true;
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'connected' || e.event === 'settings_changed') read();
    });
    socket.connect();
    return () => {
      alive.current = false;
      socket.close();
    };
  }, [read]);

  const downloading =
    status?.onnxModel?.state === 'downloading' || status?.photoHelper?.state === 'downloading';
  useEffect(() => {
    if (!downloading) return;
    const t = setInterval(read, POLL_MS);
    return () => clearInterval(t);
  }, [downloading, read]);

  const write = useCallback((patch: VoiceMediaPatch) => {
    setError('');
    const before = statusRef.current;
    if (before) setStatus({ ...before, ...patch });
    pending.current += 1;
    api
      .post<VoiceMediaStatus>('/api/voice/settings', patch)
      .then((next) => {
        pending.current -= 1;
        if (alive.current && pending.current === 0) setStatus(next);
      })
      .catch((e: unknown) => {
        pending.current -= 1;
        if (!alive.current) return;
        setStatus(before);
        setError(`Could not save that setting: ${e instanceof Error ? e.message : String(e)}`);
      });
  }, []);

  const act = useCallback((path: string, failure: string) => {
    setError('');
    api
      .post<VoiceMediaStatus>(path, {})
      .then((next) => {
        if (alive.current) setStatus(next);
      })
      .catch((e: unknown) => {
        if (alive.current) setError(`${failure} ${e instanceof Error ? e.message : String(e)}`);
      });
  }, []);

  return { status, error, write, act };
}
