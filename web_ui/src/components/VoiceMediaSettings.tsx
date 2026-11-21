// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Settings → Voice & Media: the desktop tab (lib/ui/settings/tabs/
// voice_media_tab.dart) group for group, in its order — Text-to-Speech,
// Voice Input (STT), Photo Understanding (self-hiding), Expression Images,
// Image Generation. Every value is the host's: a change here changes the
// desktop, and a change there repaints this page (useVoiceMediaWire). What
// stays desktop-only (voice calls, microphone, Whisper model, engine and
// voice setup) is listed in dev-notes/web-parity.md.

import { ExpressionImagesCard } from './voiceMedia/ExpressionImagesCard';
import { ImageGenCard } from './voiceMedia/ImageGenCard';
import { PhotoUnderstandingCard } from './voiceMedia/PhotoUnderstandingCard';
import { SttCard } from './voiceMedia/SttCard';
import { TtsCard } from './voiceMedia/TtsCard';
import { useVoiceMediaWire } from './voiceMedia/useVoiceMediaWire';

export function VoiceMediaSettings() {
  const { status, error, write, act } = useVoiceMediaWire();
  if (!status) return null;
  return (
    <div className="vm-settings" data-testid="voice-media-card">
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <TtsCard status={status} write={write} />
      <SttCard status={status} write={write} />
      <PhotoUnderstandingCard photo={status.photoHelper} act={act} />
      <ExpressionImagesCard status={status} write={write} act={act} />
      <ImageGenCard enabled={status.imageGenEnabled} write={write} />
    </div>
  );
}
