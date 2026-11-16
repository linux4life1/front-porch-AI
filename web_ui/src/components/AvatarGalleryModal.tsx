// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Avatar Gallery dialog: the one place a character's looks and expression
// images are managed, opened from the characters grid ("Avatar Gallery" in
// the card menu) and from the chat's Main Settings menu, as on the desktop.

import { AvatarManager } from './AvatarManager';

export function AvatarGalleryModal({
  characterId,
  name,
  onClose,
}: {
  characterId: string;
  name: string;
  onClose: () => void;
}) {
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal avatar-gallery-modal"
        role="dialog"
        aria-label="Avatar Gallery"
        data-testid="avatar-gallery"
        onClick={(e) => e.stopPropagation()}
      >
        <h3>Avatar Gallery — {name}</h3>
        <AvatarManager characterId={characterId} />
        <div className="modal-actions">
          <button className="primary" onClick={onClose}>
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
