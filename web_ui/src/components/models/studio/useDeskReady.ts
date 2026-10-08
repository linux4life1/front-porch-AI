// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useState } from 'react';
import { fetchReady } from './deskApi';
import type { Mode, ReadyFacts } from './types';

/**
 * What Ready says for [mode]. It reads, and never writes: the desk keeps
 * whatever graph and files the person chose. It reads again when [key]
 * changes or [refresh] is called.
 */
export function useDeskReady(mode: Mode, key: string) {
  const [facts, setFacts] = useState<ReadyFacts | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    fetchReady(mode)
      .then((body) => {
        if (live) setFacts(body);
      })
      .catch(() => {
        if (live) setFacts({ ready: false, kind: 'unreachable', reachable: false });
      });
    return () => {
      live = false;
    };
  }, [mode, key, tick]);
  const refresh = useCallback(() => setTick((n) => n + 1), []);
  return { facts, refresh };
}
