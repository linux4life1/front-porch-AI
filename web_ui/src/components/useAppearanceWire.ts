// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One Appearance card's live view of the host's choices: the block the page
// already heard (theme/appearance.ts caches it), a read on mount and on every
// reconnect, then each `settings_changed`. Every Settings card opens its own
// socket, as the rest of the page does; the block itself is shared.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import {
  type AppearanceWire,
  currentAppearanceWire,
  receiveAppearanceWire,
} from '../theme/appearance';

export function useAppearanceWire(): AppearanceWire | null {
  const [wire, setWire] = useState<AppearanceWire | null>(currentAppearanceWire);

  useEffect(() => {
    let alive = true;
    const read = () => {
      api
        .get<{ appearance?: unknown }>('/api/settings')
        .then((s) => {
          const next = receiveAppearanceWire(s.appearance);
          if (alive && next) setWire(next);
        })
        .catch((e: unknown) => console.warn('Could not read the appearance settings', e));
    };
    read();
    const socket = new ChatSocket((e) => {
      if (e.event === 'connected') read();
      else if (e.event === 'settings_changed' && e.appearance) {
        const next = receiveAppearanceWire(e.appearance);
        if (alive && next) setWire(next);
      }
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
    };
  }, []);

  return wire;
}
