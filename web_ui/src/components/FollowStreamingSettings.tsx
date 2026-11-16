// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → General → Follow streaming replies. The desktop
// puts it second in General, under My messages on the right, above the
// update row (lib/ui/settings/tabs/general_tab.dart:45-102); the web
// matches that order (one-chat-ux PR 7a).

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { DEFAULT_FOLLOW_STREAMING } from '../followStreaming';
import { SettingRow } from './SettingRow';

export function FollowStreamingSettings() {
  const [on, setOn] = useState(DEFAULT_FOLLOW_STREAMING);

  useEffect(() => {
    let cancelled = false;
    api
      .get<{ followStreamingReplies?: boolean }>('/api/settings')
      .then((r) => {
        if (cancelled) return;
        if (typeof r.followStreamingReplies === 'boolean') setOn(r.followStreamingReplies);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  const commit = (next: boolean) => {
    setOn(next);
    api.post('/api/settings', { followStreamingReplies: next }).catch(() => {});
  };

  return (
    <SettingRow
      title="Follow streaming replies"
      blurb="Keep the chat pinned to the newest words while a reply is writing, as long as you are at the bottom. Scroll up to stop."
      testid="follow-streaming-card"
    >
      <input
        className="switch"
        type="checkbox"
        checked={on}
        onChange={(e) => commit(e.target.checked)}
        aria-label="Follow streaming replies"
      />
    </SettingRow>
  );
}
