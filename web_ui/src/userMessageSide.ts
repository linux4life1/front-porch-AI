// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of desktop RealismSettings.userMessagesOnRight (default OFF):
// which side the user's messages sit on. The side is a root attribute so
// chat.css decides the layout and no transcript row has to re-render.

import { useEffect } from 'react';
import { api } from './api/client';

export function applyUserMessageSide(onRight: boolean): void {
  document.documentElement.dataset.userSide = onRight ? 'right' : 'left';
}

/** Reads the setting once when the chat opens. Left (the default) until it answers. */
export function useUserMessageSide(): void {
  useEffect(() => {
    let cancelled = false;
    api
      .get<{ realism?: { userMessagesOnRight?: boolean } }>('/api/settings')
      .then((r) => {
        if (!cancelled) applyUserMessageSide(r.realism?.userMessagesOnRight === true);
      })
      .catch(() => {
        // Host not ready: keep the left default.
      });
    return () => {
      cancelled = true;
    };
  }, []);
}
