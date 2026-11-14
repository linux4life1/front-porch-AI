// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media → Photo Understanding, the desktop's PhotoUnderstandingCard
// (lib/ui/settings/widgets/photo_understanding_card.dart). Maintenance only:
// the helper is offered in chat, so this renders nothing — heading included —
// until it is installed or downloading. Then it shows the running download
// (Cancel) or what it costs on disk (Remove).

import type { PhotoHelper } from './useVoiceMediaWire';
import { VoiceMediaCard } from './VoiceMediaCard';
import { IconImageSearch, IconTrash } from './voiceMediaIcons';

export function PhotoUnderstandingCard({
  photo,
  act,
}: {
  photo: PhotoHelper | null | undefined;
  act: (path: string, failure: string) => void;
}) {
  if (!photo || photo.state === 'absent') return null;
  const downloading = photo.state === 'downloading';
  return (
    <VoiceMediaCard
      heading="Photo Understanding"
      icon={<IconImageSearch />}
      iconTone="photo"
      title="Offline vision helper"
      testid="vm-photo"
      subtitle={
        downloading
          ? 'Downloading…'
          : `Installed (${photo.sizeLabel} on disk) — describes attached photos ` +
            "to models that can't see images. Removing frees the space; chat will " +
            "offer the download again if it's ever needed."
      }
      control={
        downloading ? (
          <button
            type="button"
            className="ghost vm-text-btn"
            onClick={() => act('/api/voice/photo/cancel', 'Could not cancel the download:')}
          >
            Cancel
          </button>
        ) : (
          <button
            type="button"
            className="ghost vm-text-btn vm-danger"
            disabled={photo.captioning}
            onClick={() => act('/api/voice/photo/remove', 'Could not remove the helper:')}
          >
            <IconTrash size={16} /> Remove
          </button>
        )
      }
    >
      {downloading && (
        <div
          className="vm-progress photo"
          role="progressbar"
          aria-label="Photo helper download"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(photo.progress * 100)}
        >
          <span style={{ width: `${Math.round(photo.progress * 100)}%` }} />
        </div>
      )}
    </VoiceMediaCard>
  );
}
