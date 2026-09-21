// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of desktop UiSettings.followStreamingReplies (default ON).

import { useEffect, useState } from 'react';
import { api } from './api/client';
import { DEFAULT_FOLLOW_STREAMING } from './pages/chat/transcriptAutoScroll';

export { DEFAULT_FOLLOW_STREAMING };

export function useFollowStreamingReplies(): boolean {
  const [follow, setFollow] = useState(DEFAULT_FOLLOW_STREAMING);
  useEffect(() => {
    let cancelled = false;
    api
      .get<{ followStreamingReplies?: boolean }>('/api/settings')
      .then((r) => {
        if (cancelled) return;
        if (typeof r.followStreamingReplies === 'boolean') {
          setFollow(r.followStreamingReplies);
        }
      })
      .catch(() => {
        // Host not ready — keep the ON default.
      });
    return () => {
      cancelled = true;
    };
  }, []);
  return follow;
}
