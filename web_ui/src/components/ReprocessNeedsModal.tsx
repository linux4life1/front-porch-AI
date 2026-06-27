// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director-redo modal: reprocess a message's Needs deltas with a written
// critique. Extracted from ChatPage (which keeps only the target message index)
// so the page stays under the file-size cap; owns its own draft/busy/error state.

import { useState } from 'react';
import { ApiError } from '../api/client';

export function ReprocessNeedsModal({
  onSubmit,
  onClose,
}: {
  /** Resolves on success (the parent then unmounts this modal); throws on failure. */
  onSubmit: (critique: string) => Promise<void>;
  onClose: () => void;
}) {
  const [critique, setCritique] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    const c = critique.trim();
    if (!c) return;
    setBusy(true);
    setError('');
    try {
      await onSubmit(c);
      // Success: the parent clears the index and this modal unmounts.
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Reprocess failed');
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div className="modal reprocess-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Reprocess Needs</span>
          <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
        </div>
        <p className="muted small">
          Enter your critique to correct the Needs Simulation deltas. The Realism Director will
          re-evaluate the scene based on your input.
        </p>
        <textarea
          value={critique}
          onChange={(e) => setCritique(e.target.value)}
          rows={4}
          placeholder="e.g. They just devoured a huge meal — hunger should jump up, not drop."
          autoFocus
        />
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button onClick={onClose} disabled={busy}>Cancel</button>
          <button className="primary" onClick={submit} disabled={busy || !critique.trim()}>
            {busy ? 'Reprocessing…' : 'Reprocess'}
          </button>
        </div>
      </div>
    </div>
  );
}
