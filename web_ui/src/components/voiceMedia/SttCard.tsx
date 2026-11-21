// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media → Voice Input (STT), the desktop's `VoiceMediaSttSection`
// (stt_section.dart): "Enable Voice Input", and while it is on the rows under
// it. The Whisper model, microphone list and voice-call settings stay on the
// desktop (maintainer ruling 2026-11-13); Auto-send transcription
// (voice_call_settings.dart) is a host setting the web's own dictation
// honours, so it is here, in the desktop's place at the end of the card.

import type { VoiceMediaPatch, VoiceMediaStatus } from './useVoiceMediaWire';
import { VoiceMediaCard, VoiceMediaSubRow } from './VoiceMediaCard';
import { IconMicrophone, IconSendArrow } from './voiceMediaIcons';

export function SttCard({
  status,
  write,
}: {
  status: VoiceMediaStatus;
  write: (p: VoiceMediaPatch) => void;
}) {
  const on = !!status.sttEnabled;
  return (
    <VoiceMediaCard
      heading="Voice Input (STT)"
      icon={<IconMicrophone />}
      title="Enable Voice Input"
      testid="vm-stt"
      control={
        <input
          type="checkbox"
          className="switch"
          aria-label="Enable Voice Input"
          checked={on}
          onChange={(e) => write({ sttEnabled: e.target.checked })}
        />
      }
    >
      {on && (
        <>
          <p className="vm-note">
            The Whisper model, the microphone and voice calls are set up in the
            desktop app.
          </p>
          {!status.sttAvailable && (
            <p className="vm-note">
              The host has not finished loading a recogniser yet. Try the mic
              again in a moment.
            </p>
          )}
          {status.autoSendTranscription !== undefined && (
            <>
              <VoiceMediaSubRow
                icon={<IconSendArrow size={16} />}
                label="Auto-send transcription"
                strong
              >
                <input
                  type="checkbox"
                  className="switch"
                  aria-label="Auto-send transcription"
                  checked={status.autoSendTranscription}
                  onChange={(e) => write({ autoSendTranscription: e.target.checked })}
                />
              </VoiceMediaSubRow>
              <p className="vm-hint">
                When enabled, transcribed text is sent automatically instead of
                being placed in the input field.
              </p>
            </>
          )}
        </>
      )}
    </VoiceMediaCard>
  );
}
