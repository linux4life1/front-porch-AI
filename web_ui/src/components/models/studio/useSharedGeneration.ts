// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';

/** The global GPU can be occupied by another Studio or the character creator. */
export function useSharedGeneration() {
  const [busy, setBusy] = useState<boolean | null>(null);
  const [problem, setProblem] = useState('');
  useEffect(() => {
    let live = true;
    let checking = false;
    const timer = window.setInterval(() => {
      if (checking) return;
      checking = true;
      api.get<{ isGenerating?: boolean }>('/api/image/config').then((value) => {
        if (live) { setBusy(value.isGenerating === true); setProblem(''); }
      }).catch(() => {
        if (live) setProblem('Could not read generation status from this computer.');
      }).finally(() => { checking = false; });
    }, 2000);
    return () => { live = false; window.clearInterval(timer); };
  }, []);
  return { busy, problem };
}
