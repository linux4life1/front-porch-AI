// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useState } from 'react';
import { api } from '../../api/client';
import { ChatSocket } from '../../api/ws';

// Porch Life's Passage of Time switch, for the clock-off line under the Needs
// switches in the character editor and creator.
//
// Rides the SAME /api/settings `realism` object PorchLifeSettings and
// useAdultThemes read (StorageService.realismSettings.passageOfTimeDefault),
// so the web cannot disagree with desktop about whether the clock is off.
//
// Reads TRUE while loading and when the settings cannot be read: the line
// explains a stopped clock, so it must never flash for the clock-on majority.
//
// Live: the server broadcasts `settings_changed` whenever a setting is written
// (on the desktop or another browser), and the hook refetches on it and on a
// reconnect, so a page left open follows the switch instead of its first read.
export function usePassageOfTime(): boolean {
  const [on, setOn] = useState(true);
  const read = useCallback((alive: () => boolean) => {
    api
      .get<{ realism?: { passageOfTimeDefault?: boolean } }>('/api/settings')
      .then((s) => {
        if (alive()) setOn(s.realism?.passageOfTimeDefault !== false);
      })
      .catch((e) => {
        console.warn('Could not read Passage of Time for the Needs note', e);
      });
  }, []);
  useEffect(() => {
    let alive = true;
    const isAlive = () => alive;
    read(isAlive);
    const socket = new ChatSocket((e) => {
      if (e.event === 'settings_changed' || e.event === 'connected') read(isAlive);
    });
    socket.connect();
    return () => {
      alive = false;
      socket.close();
    };
  }, [read]);
  return on;
}
