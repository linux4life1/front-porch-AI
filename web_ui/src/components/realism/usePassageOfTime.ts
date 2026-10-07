// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { api } from '../../api/client';

// Porch Life's Passage of Time switch, for the clock-off line under the Needs
// switches in the character editor and creator.
//
// Rides the SAME /api/settings `realism` object PorchLifeSettings and
// useAdultThemes read (StorageService.realismSettings.passageOfTimeDefault),
// so the web cannot disagree with desktop about whether the clock is off.
//
// Reads TRUE while loading and when the settings cannot be read: the line
// explains a stopped clock, so it must never flash for the clock-on majority.
export function usePassageOfTime(): boolean {
  const [on, setOn] = useState(true);
  useEffect(() => {
    let alive = true;
    api
      .get<{ realism?: { passageOfTimeDefault?: boolean } }>('/api/settings')
      .then((s) => {
        if (alive) setOn(s.realism?.passageOfTimeDefault !== false);
      })
      .catch((e) => {
        console.warn('Could not read Passage of Time for the Needs note', e);
      });
    return () => {
      alive = false;
    };
  }, []);
  return on;
}
