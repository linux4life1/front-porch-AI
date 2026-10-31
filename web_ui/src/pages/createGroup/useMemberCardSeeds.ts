// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The new-group wizard's members start from their cards: each picked
// character's card realism, read once from /api/characters/<id>/detail,
// as the seed the Realism step shows. The step lets a member be edited only
// once their card has loaded, and a card that failed to load can be asked
// for again. The relay starts a member the wizard left alone from the same
// card.

import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { RealismValues } from '../../components/realism/realismTypes';
import { memberRealismFromCard, type MemberRealism } from './groupDraft';

export interface MemberCardSeeds {
  /** Library id → that member's card seed, once it has loaded. */
  seeds: Record<string, MemberRealism>;
  /** Library ids whose card could not be read. */
  failed: string[];
  /** Ask for [id]'s card again. */
  retry: (id: string) => void;
}

export function useMemberCardSeeds(ids: string[]): MemberCardSeeds {
  const [seeds, setSeeds] = useState<Record<string, MemberRealism>>({});
  const [failed, setFailed] = useState<string[]>([]);
  const asked = useRef(new Set<string>());

  const load = useCallback((id: string) => {
    asked.current.add(id);
    setFailed((f) => f.filter((x) => x !== id));
    api
      .get<{ realism?: Partial<RealismValues> | null }>(`/api/characters/${encodeURIComponent(id)}/detail`)
      .then((d) => setSeeds((s) => ({ ...s, [id]: memberRealismFromCard(d?.realism) })))
      .catch((e) => {
        console.warn('[create-group] card seed unavailable', id, e);
        setFailed((f) => (f.includes(id) ? f : [...f, id]));
      });
  }, []);

  useEffect(() => {
    for (const id of ids) if (!asked.current.has(id)) load(id);
  }, [ids, load]);

  return { seeds, failed, retry: load };
}
