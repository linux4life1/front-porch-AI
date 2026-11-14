// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Appearance → Chat appearance → Mood on the character and its
// Drama. Shown only while the Realism Engine is on, as on the desktop
// ("it is about the character, not the weather"). Split out of
// AppearanceSettings when the web Settings matched the desktop's seven
// tabs (one-chat-ux PR 7a).

import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';

type MoodLevel = 'off' | 'portrait' | 'all';
const MOOD: { value: MoodLevel; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'portrait', label: 'Portrait and needs' },
  { value: 'all', label: 'Portrait, needs and bubbles' },
];
const asMood = (v: unknown): MoodLevel => (v === 'portrait' || v === 'all' ? v : 'off');
// The Drama slider's range, the desktop's own (kMoodDramaMin..Max).
const asDrama = (v: unknown): number =>
  typeof v === 'number' && Number.isFinite(v) ? Math.min(1.6, Math.max(0.4, v)) : 1;
/** Writes the Drama; on unmount nobody is left to show a failure, so it is logged. */
const postDrama = (value: number) =>
  api.post('/api/settings', { moodDrama: value }).catch((e: unknown) => {
    console.warn('Could not change the mood drama', e);
    throw e;
  });

export function MoodOnCharacterSettings() {
  const [error, setError] = useState('');
  // Appearance → Mood on the character and its Drama (null until read).
  const [mood, setMood] = useState<MoodLevel | null>(null);
  const [drama, setDrama] = useState<number | null>(null);
  // The Realism Engine gates this section, as on the desktop (a missing
  // read counts as on).
  const [realismAllowed, setRealismAllowed] = useState(true);
  // A drag of the Drama posts once it settles, not on every step; a
  // value still waiting when the card closes is posted then.
  const dramaPost = useRef<{ timer: ReturnType<typeof setTimeout>; value: number } | null>(null);

  // Live: the server broadcasts `settings_changed` whenever a setting is
  // written (on the desktop or another browser), so the control re-reads on
  // it and on a reconnect instead of keeping its first read.
  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{
          moodOnCharacter?: unknown; moodDrama?: unknown;
          realism?: { realismAllowed?: unknown };
        }>('/api/settings')
        .then((s) => {
          if (!alive) return;
          setMood(asMood(s.moodOnCharacter));
          setDrama(asDrama(s.moodDrama));
          setRealismAllowed(s.realism?.realismAllowed !== false);
        })
        .catch((e: unknown) => console.warn('Could not read the mood setting', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read();
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
      const pending = dramaPost.current;
      if (pending) {
        clearTimeout(pending.timer);
        dramaPost.current = null;
        postDrama(pending.value).catch(() => undefined);
      }
    };
  }, []);

  const setMoodLevel = (next: MoodLevel) => {
    const before = mood;
    setMood(next);
    setError('');
    api.post('/api/settings', { moodOnCharacter: next }).catch((e: unknown) => {
      setMood(before);
      setError(`Could not change Mood on the character: ${String(e)}`);
    });
  };

  const changeDrama = (next: number) => {
    setDrama(next);
    setError('');
    if (dramaPost.current) clearTimeout(dramaPost.current.timer);
    dramaPost.current = {
      value: next,
      timer: setTimeout(() => {
        dramaPost.current = null;
        postDrama(next).catch((e: unknown) => {
          setError(`Could not change the mood drama: ${String(e)}`);
        });
      }, 250),
    };
  };

  if (!realismAllowed) return null;

  return (
    <section className="card" data-testid="mood-on-character">
      <label>
        Mood on the character
        <select
          value={mood ?? 'off'}
          disabled={mood === null}
          onChange={(e) => setMoodLevel(e.target.value as MoodLevel)}
          aria-label="Mood on the character"
        >
          {MOOD.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </label>
      <label>
        Drama
        <input
          type="range"
          min={40}
          max={160}
          step={10}
          value={Math.round((drama ?? 1) * 100)}
          disabled={mood === null || mood === 'off' || drama === null}
          onChange={(e) => changeDrama(Number(e.target.value) / 100)}
          aria-label="Drama"
        />
      </label>
      {error && <p className="error">{error}</p>}
      <p className="reading-blurb">Each character's mood on their portrait and needs bars, in their own Realism colours. Needs Realism on for the chat. The desktop's settings; changing them here changes them there too.</p>
    </section>
  );
}
