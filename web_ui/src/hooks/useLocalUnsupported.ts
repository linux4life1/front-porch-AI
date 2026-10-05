// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Whether the host says it cannot run KoboldCpp (`localUnsupported` on its
// status: an Intel Mac). The host is only sure once it has read its
// processor, a moment after it starts, so while [active] this asks again
// every few seconds and follows every answer; it never keeps the first one.
// An older app does not say, which reads as false.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

const ASK_EVERY_MS = 5000;

export function useLocalUnsupported(active = true): boolean {
  const [unsupported, setUnsupported] = useState(false);
  useEffect(() => {
    if (!active) return;
    let open = true;
    const ask = () =>
      api
        .get<{ localUnsupported?: boolean }>('/api/backend/status')
        .then((r) => {
          if (open) setUnsupported(r?.localUnsupported === true);
        })
        // A missed answer keeps the last one; the next ask follows.
        .catch(() => {});
    void ask();
    const t = setInterval(() => void ask(), ASK_EVERY_MS);
    return () => {
      open = false;
      clearInterval(t);
    };
  }, [active]);
  return unsupported;
}
