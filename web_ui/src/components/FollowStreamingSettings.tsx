// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → General → Follow streaming replies.
// Desktop sits this immediately above Dark mode; web has no Dark mode
// card, so this sits immediately above Reading size.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { DEFAULT_FOLLOW_STREAMING } from '../followStreaming';

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
    <section className="card" data-testid="follow-streaming-card">
      <h3>Follow streaming replies</h3>
      <p className="reading-blurb">
        Jump to the live reply when it starts writing, even if you were
        reading older messages. Scroll up to stop following.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on}
          onChange={(e) => commit(e.target.checked)}
          aria-label="Follow streaming replies"
        />
        {' '}Follow streaming replies
      </label>
    </section>
  );
}
