// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of the desktop's Advanced Launch Options → "Keep recent chats
// ready": how many chats besides the open one the host's KoboldCpp keeps
// ready in memory. Off (the default) keeps only the open chat and lets it go
// when the chat is left. Saved at once, as the desktop chips are. Hidden on a
// host that does not have the setting.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

interface KeepRecent {
  koboldKeepRecentChats?: number;
  koboldKeepRecentChoices?: number[];
}

/** The desktop chip's name for a choice. */
export function keepRecentLabel(chats: number): string {
  return chats === 0 ? 'Off' : String(chats);
}

export function KeepRecentChatsSettings() {
  const [chats, setChats] = useState<number | null>(null);
  const [choices, setChoices] = useState<number[]>([]);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<KeepRecent>('/api/settings')
      .then((r) => {
        if (cancelled || typeof r.koboldKeepRecentChats !== 'number') return;
        setChats(r.koboldKeepRecentChats);
        setChoices(r.koboldKeepRecentChoices ?? [0, 1, 2, 3, 4]);
      })
      .catch(() => {
        // Host not ready: the card stays hidden until the page is opened again.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (chats === null) return null;

  const commit = (next: number) => {
    const before = chats;
    setChats(next);
    setProblem('');
    api.post('/api/settings', { koboldKeepRecentChats: next }).catch(() => {
      setChats(before);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="kobold-keep-recent-card">
      <h3>Keep recent chats ready</h3>
      <p className="reading-blurb">
        Besides the chat you have open, keeps the ones you used last ready in
        the computer&apos;s memory, so going back to one is quick. Off keeps
        only the open chat, and frees its memory when you leave it. Fewer are
        kept when memory is short.
      </p>
      <label>
        Recent chats kept ready
        <select
          value={chats}
          onChange={(e) => commit(Number(e.target.value))}
          data-testid="kobold-keep-recent-select"
        >
          {choices.map((n) => (
            <option key={n} value={n}>
              {keepRecentLabel(n)}
            </option>
          ))}
        </select>
      </label>
      {problem && (
        <p className="error" role="alert">
          {problem}
        </p>
      )}
    </section>
  );
}
