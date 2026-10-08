// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useRef, useState } from 'react';
import { api } from '../../../api/client';
import { ChatSocket } from '../../../api/ws';
import { onPackChanged, announcePackChange } from './packApi';

/** The global GPU can be occupied by another Studio or the character creator. */
export function useSharedGeneration(localBusy = false) {
  const [busy, setBusy] = useState<boolean | null>(null);
  const [problem, setProblem] = useState('');
  const refreshRef = useRef<(() => void) | null>(null);
  useEffect(() => {
    let live = true;
    let checking = false;
    const refresh = () => {
      if (checking) return;
      checking = true;
      api.get<{ isGenerating?: boolean }>('/api/image/config').then((value) => {
        if (live) { setBusy(value.isGenerating === true); setProblem(''); }
      }).catch(() => {
        if (live) setProblem('Could not read generation status from this computer.');
      }).finally(() => { checking = false; });
    };
    const visible = () => { if (!document.hidden) refresh(); };
    const socket = new ChatSocket((event) => {
      if (event.event === 'connected') { refresh(); announcePackChange(); }
      if (event.event === 'expression_pack_changed') announcePackChange();
      if (event.event === 'image_progress') {
        if (live) setBusy(event.generating === true);
        if (event.generating !== wasGenerating) {
          wasGenerating = event.generating;
          announcePackChange();
        }
      }
    });
    let wasGenerating: boolean | undefined;
    refresh();
    socket.connect();
    const remove = onPackChanged(refresh);
    window.addEventListener('focus', visible);
    document.addEventListener('visibilitychange', visible);
    refreshRef.current = visible;
    return () => {
      live = false;
      socket.close();
      remove();
      window.removeEventListener('focus', visible);
      document.removeEventListener('visibilitychange', visible);
      refreshRef.current = null;
    };
  }, []);
  useEffect(() => {
    if (!busy && !localBusy) return;
    const timer = window.setInterval(() => refreshRef.current?.(), 2000);
    return () => window.clearInterval(timer);
  }, [busy, localBusy]);
  return { busy, problem };
}
