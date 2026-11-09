// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The group's turn order for the desktop header's second line
// (`N characters • Round Robin`). The chat state snapshot does not carry
// it; the tools snapshot does. The sidebar is on screen whenever this
// fetches (desktop group chat), so this GET is not the "hidden panel"
// fetch the mount audit fought — it just moves the same read the sidebar
// makes up to the page so the header can print it.

import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { type ToolsState } from '../../components/ChatToolsShared';

/** `'random'` maps the tools facade's own word; anything else reads as the
 *  default, matching `stoop/stoopCardBody.ts`. */
export function turnOrderLabel(turnOrder: string): string {
  return turnOrder === 'random' ? 'Random' : 'Round Robin';
}

/** The group's stored turn order, or null while unknown / not a group. */
export function useGroupTurnOrder(
  enabled: boolean,
  reloadKey: number,
): string | null {
  const [turnOrder, setTurnOrder] = useState<string | null>(null);

  useEffect(() => {
    if (!enabled) {
      setTurnOrder(null);
      return;
    }
    let live = true;
    api
      .get<ToolsState>('/api/chat/tools')
      .then((t) => live && setTurnOrder(t.group?.turnOrder ?? null))
      .catch(() => {
        /* no active group — the header shows just the count */
      });
    return () => {
      live = false;
    };
  }, [enabled, reloadKey]);

  return turnOrder;
}
