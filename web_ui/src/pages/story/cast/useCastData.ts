// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the Cast screen asks the app besides the story: the voices a character
// can read aloud with, the library cards' art (a character with the same name
// borrows it as a portrait), and whether an image engine is set up to paint one.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import type { StoryVoice } from '../../../storyTypes';

export function useCastData(): { voices: StoryVoice[]; art: Record<string, string>; canPaint: boolean } {
  const [voices, setVoices] = useState<StoryVoice[]>([]);
  const [art, setArt] = useState<Record<string, string>>({});
  const [canPaint, setCanPaint] = useState(false);

  useEffect(() => {
    // Each of these is an extra: without it the card shows less, never breaks.
    api.get<{ voices: StoryVoice[] }>('/api/stories/voices').then((r) => setVoices(r.voices ?? [])).catch(() => setVoices([]));
    // Every card, not just the folder the library shows.
    api.get<{ id: string; name: string }[]>('/api/characters?scope=allCharacters')
      .then((r) => setArt(Object.fromEntries(r.map((c) => [c.name, `/api/characters/${c.id}/avatar?w=128`]))))
      .catch(() => setArt({}));
    api.get<{ isConfigured?: boolean }>('/api/image/config').then((r) => setCanPaint(r.isConfigured === true)).catch(() => setCanPaint(false));
  }, []);

  return { voices, art, canPaint };
}
