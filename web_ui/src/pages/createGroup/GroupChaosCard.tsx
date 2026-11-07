// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Realism: Group Chaos (Chance Time) and its adult events. Web
// twin of the Chaos card atop the desktop GroupRealismStep; it stands apart
// from the Realism switch, and the adult switch shows only with 18+ on.

import { ToggleRow } from '../../components/realism/controls';
import type { GroupDraft } from './groupDraft';

export function GroupChaosCard({
  draft,
  set,
  adult,
}: {
  draft: GroupDraft;
  set: (patch: Partial<GroupDraft>) => void;
  /** The install's 18+ master switch. */
  adult: boolean;
}) {
  return (
    <div className="gs-panel gw-member" data-testid="group-chaos">
      <ToggleRow
        label="Group Chaos (Chance Time)"
        hint="Random narrative events during roleplay. Can include NSFW events when enabled."
        value={draft.chaosModeEnabled}
        onChange={(b) => set({ chaosModeEnabled: b })}
      />
      {draft.chaosModeEnabled && adult && (
        <ToggleRow
          label="Include NSFW events"
          value={draft.chaosNsfwEnabled}
          onChange={(b) => set({ chaosNsfwEnabled: b })}
        />
      )}
    </div>
  );
}
