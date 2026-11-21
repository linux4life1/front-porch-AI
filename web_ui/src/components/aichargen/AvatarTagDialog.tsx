// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review rail's tag dialog (desktop upload_tag_dialog.dart): a second
// upload is either a gallery look or an expression image. The desktop asks
// with the picture itself, a "Gallery look" chip, and every emotion as a
// chip — tapping one answers the question, Cancel walks away.

import { useEffect, useState } from 'react';
import { HangerIcon } from './creatorIcons';
import { EMOTION_EMOJI, EMOTION_LABELS } from './avatarRailApi';

export function AvatarTagDialog({
  file,
  onConfirm,
  onClose,
  busy,
}: {
  /** The picture being tagged, shown at the dialog's head. */
  file: File;
  onConfirm: (label: string | null) => void;
  onClose: () => void;
  busy?: boolean;
}) {
  const [thumb, setThumb] = useState<string>();
  useEffect(() => {
    const url = URL.createObjectURL(file);
    setThumb(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  const pick = (label: string | null) => {
    if (!busy) onConfirm(label);
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div
        className="modal cg-r-tag-modal"
        role="dialog"
        aria-label="What is this image?"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="cg-r-tag-body">
          <header className="cg-tag-head">
            {thumb && <img src={thumb} alt="" className="cg-tag-thumb" />}
            <h3>What is this image?</h3>
          </header>
          <button
            type="button"
            className="cg-tag-look"
            disabled={busy}
            onClick={() => pick(null)}
          >
            <HangerIcon /> Gallery look (outfit / scene — no emotion)
          </button>
          <p className="cg-tag-or">Or tag it as an expression image:</p>
          <div className="cg-tag-chips">
            {EMOTION_LABELS.map((emotion) => (
              <button
                key={emotion}
                type="button"
                className="cg-tag-chip"
                disabled={busy}
                onClick={() => pick(emotion)}
              >
                {EMOTION_EMOJI[emotion]} {emotion}
              </button>
            ))}
          </div>
        </div>
        <footer className="cg-r-lore-foot cg-tag-foot">
          <button type="button" className="ghost" disabled={busy} onClick={() => !busy && onClose()}>
            Cancel
          </button>
        </footer>
      </div>
    </div>
  );
}
