// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The new-group wizard's members start from their cards: each picked
// character's card realism, read once from /api/characters/<id>/detail,
// as the seed the Realism step shows and the presets build on. The relay
// starts a member the wizard left alone from the same card.

import { useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { RealismValues } from '../../components/realism/realismTypes';
import { memberRealismFromCard, type MemberRealism } from './groupDraft';

/** Library id → that member's card seed, for every id in [ids] whose card
 *  has loaded. */
export function useMemberCardSeeds(ids: string[]): Record<string, MemberRealism> {
  const [seeds, setSeeds] = useState<Record<string, MemberRealism>>({});
  const asked = useRef(new Set<string>());
  useEffect(() => {
    for (const id of ids) {
      if (asked.current.has(id)) continue;
      asked.current.add(id);
      api
        .get<{ realism?: Partial<RealismValues> | null }>(`/api/characters/${encodeURIComponent(id)}/detail`)
        .then((d) => setSeeds((s) => ({ ...s, [id]: memberRealismFromCard(d?.realism) })))
        .catch((e) => {
          // Asked again on the next roster change; until then the step
          // shows neutral and the relay still starts the member from
          // their card.
          asked.current.delete(id);
          console.warn('[create-group] card seed unavailable', id, e);
        });
    }
  }, [ids]);
  return seeds;
}
