// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The new-group wizard's per-member Voice, the phone's twin of the voice
// picker on each desktop Members row. A member with no pick keeps the card's
// own voice; '' is "Use the global voice"; anything else is the voice id.

import { useEffect, useState } from 'react';

import { api } from '../../api/client';

interface VoiceStatus {
  globalVoice?: string;
  voices?: { id: string; name: string; gender?: string }[];
}

/** The select's value for "no pick": a member keeps the card's own voice. */
const OWN = '__own__';

export function MemberVoicePicks({
  members,
  voices,
  set,
}: {
  members: { id: string; name: string }[];
  voices: Record<string, string>;
  set: (next: Record<string, string>) => void;
}) {
  const [status, setStatus] = useState<VoiceStatus | null>(null);
  useEffect(() => {
    api
      .get<VoiceStatus>('/api/voice/status')
      .then(setStatus)
      .catch(() => setStatus(null));
  }, []);

  const list = status?.voices ?? [];
  // As on the character page: no voices until text-to-speech is set up.
  if (list.length === 0) return null;
  const globalName = status?.globalVoice
    ? (list.find((v) => v.id === status.globalVoice)?.name ?? status.globalVoice)
    : null;

  const pick = (id: string, value: string) => {
    const next = { ...voices };
    if (value === OWN) delete next[id];
    else next[id] = value;
    set(next);
  };

  return (
    <div className="cg-field">
      <span className="cg-field-label">Voices</span>
      {members.map((m) => (
        <label key={m.id} className="cg-field">
          <span>{m.name}</span>
          <select
            className="voice-select"
            aria-label={`${m.name}'s voice`}
            value={m.id in voices ? voices[m.id] : OWN}
            onChange={(e) => pick(m.id, e.target.value)}
          >
            <option value={OWN}>Their own voice</option>
            <option value="">
              Use the global voice{globalName ? ` (${globalName})` : ' (none picked yet)'}
            </option>
            {list.map((v) => (
              <option key={v.id} value={v.id}>
                {v.gender === 'Male' ? '♂ ' : v.gender === 'Female' ? '♀ ' : '⚬ '}
                {v.name}
              </option>
            ))}
          </select>
        </label>
      ))}
    </div>
  );
}
