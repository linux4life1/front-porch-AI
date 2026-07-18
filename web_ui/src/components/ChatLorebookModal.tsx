// Copyright (C) 2026 Front Porch AI — SPDX-License-Identifier: AGPL-3.0-or-later
//
// The per-chat lorebook manager (desktop "This Chat" sidebar section parity):
// lore that lives and dies with this one conversation. Loads the full-fidelity
// rows (opaque `ext` preserved), edits via the shared LoreEntriesEditor, and
// saves back through /api/chat/lorebook.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { LoreEntriesEditor, type LoreEntry } from './LoreEntriesEditor';

export function ChatLorebookModal({ onClose }: { onClose: () => void }) {
  const [entries, setEntries] = useState<LoreEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api
      .get<{ entries: LoreEntry[] }>('/api/chat/lorebook')
      .then((r) => setEntries(r.entries ?? []))
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load'));
  }, []);

  const save = async () => {
    if (entries == null) return;
    setSaving(true);
    try {
      await api.post('/api/chat/lorebook', { entries });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Save failed');
      setSaving(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal lore-chat-modal" onClick={(e) => e.stopPropagation()}>
        <h3>This chat's lorebook</h3>
        <p className="muted small">
          Lore for this conversation only — it never touches the character or
          your Worlds library.
        </p>
        {error && <p className="danger small">{error}</p>}
        {entries == null ? (
          <p className="muted small">Loading…</p>
        ) : (
          <LoreEntriesEditor entries={entries} onChange={setEntries} />
        )}
        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>Cancel</button>
          <button onClick={save} disabled={saving || entries == null}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      </div>
    </div>
  );
}
