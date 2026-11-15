// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Realism step talks to the saved character: its Realism
// values from the editor's own read (`/detail`'s `realism` block), and a
// save of those values alone through the editor's update route, which
// changes only the keys it is sent — the greetings and profile saved a
// moment earlier stay as they are.

import { api } from '../../api/client';
import { type RealismValues, realismFromDetail } from '../realism/realismTypes';

const enc = encodeURIComponent;

export async function loadRealism(id: string): Promise<RealismValues> {
  const d = await api.get<{ realism?: Partial<RealismValues> | null }>(`/api/characters/${enc(id)}/detail`);
  return realismFromDetail(d.realism);
}

/** The Realism block alone. The greeting starting states ride with the
 *  greetings (the Greetings step saves them), so they are left out. */
export function saveRealism(id: string, v: RealismValues): Promise<unknown> {
  const { greetingSeeds: _seeds, ...realism } = v;
  void _seeds;
  return api.post(`/api/characters/${enc(id)}`, realism);
}
