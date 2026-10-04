// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of the desktop's Advanced Launch Options → "Free graphics
// memory when idle": how long the host's KoboldCpp may sit with nothing to do
// before its model is unloaded. Saved at once, as the desktop chips are.
// Hidden on a host that does not have the setting.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

interface IdleUnload {
  koboldIdleUnloadMinutes?: number;
  koboldIdleUnloadChoices?: number[];
}

/** The desktop chip's name for a choice. */
export function idleUnloadLabel(minutes: number): string {
  if (minutes === 0) return 'Off';
  if (minutes === 60) return '1 hour';
  return `${minutes} min`;
}

export function IdleUnloadSettings() {
  const [minutes, setMinutes] = useState<number | null>(null);
  const [choices, setChoices] = useState<number[]>([]);
  const [problem, setProblem] = useState('');

  useEffect(() => {
    let cancelled = false;
    api
      .get<IdleUnload>('/api/settings')
      .then((r) => {
        if (cancelled || typeof r.koboldIdleUnloadMinutes !== 'number') return;
        setMinutes(r.koboldIdleUnloadMinutes);
        setChoices(r.koboldIdleUnloadChoices ?? [0, 10, 30, 60]);
      })
      .catch(() => {
        // Host not ready: the card stays hidden until the page is opened again.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (minutes === null) return null;

  const commit = (next: number) => {
    const before = minutes;
    setMinutes(next);
    setProblem('');
    api.post('/api/settings', { koboldIdleUnloadMinutes: next }).catch(() => {
      setMinutes(before);
      setProblem('That could not be saved. Check that the app is running, then try again.');
    });
  };

  return (
    <section className="card" data-testid="kobold-idle-card">
      <h3>Free graphics memory when idle</h3>
      <p className="reading-blurb">
        Unloads the model when KoboldCpp on the computer has had nothing to do
        for this long, so other programs can use the graphics memory. The
        first reply after that takes longer to start.
      </p>
      <label>
        Idle time before unloading
        <select
          value={minutes}
          onChange={(e) => commit(Number(e.target.value))}
          data-testid="kobold-idle-select"
        >
          {choices.map((m) => (
            <option key={m} value={m}>
              {idleUnloadLabel(m)}
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
