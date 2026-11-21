// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's per-entry lorebook dialog (desktop
// lib/ui/dialogs/lorebook_entry_dialog.dart): Simple and Advanced tabs over
// the shared LoreEntryFields, so the web authors an entry exactly as the
// character editor does. Save writes the draft; Cancel changes nothing.

import { useState } from 'react';
import { LoreEntryFields, type LoreEntry } from '../LoreEntriesEditor';

export function ReviewLoreEntryModal({
  entry,
  onSave,
  onClose,
}: {
  entry: LoreEntry;
  onSave: (next: LoreEntry) => void;
  onClose: () => void;
}) {
  const [draft, setDraft] = useState<LoreEntry>(entry);
  const [tab, setTab] = useState<'simple' | 'advanced'>('simple');
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal cg-r-lore-modal"
        role="dialog"
        aria-label="Edit Lorebook Entry"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="cg-r-lore-head">
          <h3>Edit Lorebook Entry</h3>
          <div className="cg-r-tabs" role="tablist" aria-label="Entry fields">
            <button
              type="button"
              role="tab"
              aria-selected={tab === 'simple'}
              className={tab === 'simple' ? 'active' : undefined}
              onClick={() => setTab('simple')}
            >
              Simple
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={tab === 'advanced'}
              className={tab === 'advanced' ? 'active' : undefined}
              onClick={() => setTab('advanced')}
            >
              Advanced
            </button>
          </div>
          <button type="button" className="ghost" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </header>
        <div className="cg-r-lore-body">
          <LoreEntryFields
            entry={draft}
            update={(patch) => setDraft({ ...draft, ...patch })}
            tab={tab}
          />
        </div>
        <footer className="cg-r-lore-foot">
          <button type="button" className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button type="button" className="primary" onClick={() => onSave(draft)}>
            Save
          </button>
        </footer>
      </div>
    </div>
  );
}
