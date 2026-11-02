// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The presets, links, recommended values and switch notice, kept current:
// every model switch ends in a settings write on the host, which broadcasts
// `settings_changed`, so a page refetches on it and on a reconnect instead
// of keeping its first read. Writes answer with the same body.
//
// [follow] false reads once and opens no socket of its own: for a card
// that is already polling, or a picker inside a short-lived sheet.

import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { genPresetsApi, type GenPresets } from './genPresets';

export function useGenPresets(follow = true) {
  const [data, setData] = useState<GenPresets | null>(null);
  const [error, setError] = useState('');
  const alive = useRef(true);

  const read = useCallback(() => {
    genPresetsApi
      .read()
      .then((next) => {
        if (alive.current) setData(next);
      })
      .catch((e) => console.warn('[gen-presets] read failed', e));
  }, []);

  useEffect(() => {
    alive.current = true;
    read();
    if (!follow) {
      return () => {
        alive.current = false;
      };
    }
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive.current = false;
      socket.close();
    };
  }, [read, follow]);

  /** Posts one action; the answer replaces the state. Null on failure,
   *  which is said in [error]. */
  const act = useCallback(async (action: string, body: Record<string, unknown> = {}) => {
    setError('');
    try {
      const next = await genPresetsApi.post(action, body);
      if (alive.current) setData(next);
      return next;
    } catch (e) {
      if (alive.current) {
        setError(e instanceof ApiError || e instanceof Error ? e.message : String(e));
      }
      return null;
    }
  }, []);

  return { data, error, act, reload: read };
}
