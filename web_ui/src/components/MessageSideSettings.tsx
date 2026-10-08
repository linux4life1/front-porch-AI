// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of Settings → General → My messages on the right. Desktop sits
// it immediately above Follow streaming replies; so does this.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { applyUserMessageSide } from '../userMessageSide';

export function MessageSideSettings() {
  const [on, setOn] = useState(false);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<{ realism?: { userMessagesOnRight?: boolean } }>('/api/settings')
      .then((r) => {
        if (!cancelled) setOn(r.realism?.userMessagesOnRight === true);
      })
      .catch(() => {
        // Host not ready: the switch shows the left default.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const commit = (next: boolean) => {
    setOn(next);
    setProblem('');
    applyUserMessageSide(next);
    api.post('/api/settings', { realism: { userMessagesOnRight: next } }).catch(() => {
      setOn(!next);
      applyUserMessageSide(!next);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="message-side-card">
      <h3>My messages on the right</h3>
      <p className="reading-blurb">
        Off, your messages sit on the left, like the character&apos;s. On, they
        move to the right, the way chat looked before.
      </p>
      <label>
        <input
          type="checkbox"
          checked={on}
          onChange={(e) => commit(e.target.checked)}
          aria-label="My messages on the right"
        />
        {' '}My messages on the right
      </label>
      {problem && <p className="error" role="alert">{problem}</p>}
    </section>
  );
}
