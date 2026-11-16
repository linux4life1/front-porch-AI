// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// General → Auto-check for Updates: the desktop's own switch, host-wide. The
// key is absent on a host without the update service, and this card then
// renders nothing (no dead switch). The switch does not ride
// `settings_changed` (the update service is not a settings notifier), so the
// card re-reads when the tab becomes visible and on reconnect.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import { SettingRow } from './SettingRow';

/** undefined: not read yet; null: this host has no update service. */
type AutoCheck = boolean | null | undefined;

export function AutoCheckSettings() {
  const [enabled, setEnabled] = useState<AutoCheck>(undefined);
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{ autoCheckForUpdates?: unknown }>('/api/settings')
        .then((s) => {
          if (!alive) return;
          const v = s.autoCheckForUpdates;
          setEnabled(typeof v === 'boolean' ? v : null);
        })
        .catch((e: unknown) => console.warn('Could not read the update setting', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'connected') read();
    });
    socket.connect();
    // A desktop toggle fires no event this page hears; coming back to the
    // tab re-reads instead of showing a stale switch.
    const onVisible = () => {
      if (document.visibilityState === 'visible') read();
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      alive = false;
      socket.close();
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, []);

  if (enabled === undefined || enabled === null) return null;

  const change = (next: boolean) => {
    const before = enabled;
    setEnabled(next);
    setError('');
    api.post('/api/settings', { autoCheckForUpdates: next }).catch((e: unknown) => {
      setEnabled(before);
      setError(`Could not change the update setting: ${String(e)}`);
    });
  };

  return (
    <>
      <SettingRow
        title="Auto-check for Updates"
        blurb="Look for a newer release when the app starts."
        testid="auto-check-card"
      >
        <input
          className="switch"
          type="checkbox"
          checked={enabled}
          onChange={(e) => change(e.target.checked)}
          aria-label="Auto-check for Updates"
        />
      </SettingRow>
      {error && <p className="error">{error}</p>}
    </>
  );
}
