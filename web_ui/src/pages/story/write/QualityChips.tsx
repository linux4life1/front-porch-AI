// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The quality chips under a beat ("412 words", "Dialogue 18%", "2 banned
// phrases"). The host scores the passage (the same StoryQuality the desktop
// runs); good reads teal, warn honey, bad red.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import type { QualityChip } from '../../../storyTypes';
import { Chip } from '../setup/primitives';

export function QualityChips({ text, banned }: { text: string; banned: string[] }) {
  const [chips, setChips] = useState<QualityChip[]>([]);
  // The phrase list is a new array every render; its text is what changes the score.
  const bannedText = banned.join('\n');

  useEffect(() => {
    let live = true;
    api.post<{ chips: QualityChip[] }>('/api/stories/quality', { text, banned: bannedText ? bannedText.split('\n') : [] })
      .then((r) => { if (live) setChips(r.chips); })
      .catch((e) => console.warn('[story] quality chips unavailable', e));
    return () => { live = false; };
  }, [text, bannedText]);

  if (chips.length === 0) return null;
  return (
    <div className="s-chips" data-testid="story-quality">
      {chips.map((c, i) => <Chip key={i} tone={c.tone === 'plain' ? '' : c.tone}>{c.label}</Chip>)}
    </div>
  );
}
