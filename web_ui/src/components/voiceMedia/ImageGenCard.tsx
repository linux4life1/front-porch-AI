// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media → Image Generation, the desktop's ImageGenEnableSection
// (lib/ui/settings/widgets/image_gen_enable_section.dart): the on/off switch
// for the Image Studio button in chat. The backend, model and LoRAs are set in
// the Image Studio itself.

import type { VoiceMediaPatch } from './useVoiceMediaWire';
import { VoiceMediaCard } from './VoiceMediaCard';
import { IconAwesome } from './voiceMediaIcons';

export function ImageGenCard({
  enabled,
  write,
}: {
  enabled: boolean | undefined;
  write: (p: VoiceMediaPatch) => void;
}) {
  if (enabled === undefined) return null;
  return (
    <VoiceMediaCard
      heading="Image Generation"
      icon={<IconAwesome />}
      iconTone={enabled ? 'accent' : 'off'}
      title="Image Generation"
      subtitle={enabled ? 'Enabled — Image Studio button shown in chat' : 'Disabled'}
      testid="vm-image-gen"
      control={
        <input
          type="checkbox"
          className="switch"
          aria-label="Image Generation"
          checked={enabled}
          onChange={(e) => write({ imageGenEnabled: e.target.checked })}
        />
      }
    >
      {enabled && (
        <p className="vm-hint">
          Adds the ✨ Image Studio button to the chat toolbar. Configure the
          backend, model, and LoRAs inside the Image Studio.
        </p>
      )}
    </VoiceMediaCard>
  );
}
