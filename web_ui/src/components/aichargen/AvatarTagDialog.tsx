// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review rail's tag dialog (desktop upload_tag_dialog.dart): a second
// upload is either a gallery look or an expression image, and an expression
// must name one of the EmotionLabels values.

import { useState } from 'react';
import { EMOTION_LABELS } from './avatarRailApi';

export function AvatarTagDialog({
  onConfirm,
  onClose,
  busy,
}: {
  onConfirm: (label: string | null) => void;
  onClose: () => void;
  busy?: boolean;
}) {
  const [kind, setKind] = useState<'look' | 'expression'>('expression');
  const [label, setLabel] = useState<string>(EMOTION_LABELS[0]);
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal cg-r-tag-modal"
        role="dialog"
        aria-label="Tag this image"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="cg-r-lore-head">
          <h3>Tag this image</h3>
          <button type="button" className="ghost" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </header>
        <div className="cg-r-tag-body">
          <label className="cg-r-tag-choice">
            <input
              type="radio"
              name="avatar-tag-kind"
              checked={kind === 'look'}
              onChange={() => setKind('look')}
            />
            <span>
              <strong>Gallery look</strong>
              <small>An outfit, scene or seasonal picture — shown in the gallery, never the expression engine.</small>
            </span>
          </label>
          <label className="cg-r-tag-choice">
            <input
              type="radio"
              name="avatar-tag-kind"
              checked={kind === 'expression'}
              onChange={() => setKind('expression')}
            />
            <span>
              <strong>Expression image</strong>
              <small>Used by the expression engine when the character feels this.</small>
            </span>
          </label>
          {kind === 'expression' && (
            <label className="cg-field">
              <span className="cg-field-label">Emotion</span>
              <select value={label} onChange={(e) => setLabel(e.target.value)}>
                {EMOTION_LABELS.map((e) => (
                  <option key={e} value={e}>
                    {e}
                  </option>
                ))}
              </select>
            </label>
          )}
        </div>
        <footer className="cg-r-lore-foot">
          <button type="button" className="ghost" onClick={onClose}>
            Cancel
          </button>
          <button
            type="button"
            className="primary"
            disabled={busy}
            onClick={() => onConfirm(kind === 'look' ? null : label)}
          >
            Add image
          </button>
        </footer>
      </div>
    </div>
  );
}
