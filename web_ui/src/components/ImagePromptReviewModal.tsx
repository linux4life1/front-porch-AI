// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Review/edit the AI-crafted /image prompt before it goes to the image
// backend — the web counterpart of the desktop ImagePromptReviewDialog.
// Opens when /api/chat/state carries `imagePromptReview` (the engine parks
// the generation on a completer until this resolves). Can be turned off with
// the "Review AI prompts" toggle in the image settings.

import { useState } from 'react';

export function ImagePromptReviewModal({
  prompt,
  onGenerate,
  onCancel,
}: {
  prompt: string;
  onGenerate: (edited: string) => void;
  onCancel: () => void;
}) {
  const [draft, setDraft] = useState(prompt);

  return (
    <div className="drawer-backdrop center" onClick={onCancel}>
      <div className="modal reprocess-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>🎨 Review image prompt</span>
          <button className="link-btn" onClick={onCancel}>Close</button>
        </div>
        <p className="muted small">
          This is what will be sent to the image backend — edit it freely.
        </p>
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          rows={5}
          autoFocus
        />
        <div className="modal-actions">
          <button onClick={onCancel}>Cancel</button>
          <button
            className="primary"
            onClick={() => draft.trim() && onGenerate(draft.trim())}
            disabled={!draft.trim()}
          >
            Generate
          </button>
        </div>
      </div>
    </div>
  );
}
