// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media → Text-to-Speech, the desktop's `_TtsSection`
// (voice_media_tab.dart): the engine's name and "Enabled — Voice: …" /
// "Disabled". The desktop's Configure button (engine + voice setup) stays on
// the desktop (maintainer ruling 2026-11-13); in its place the web keeps the
// switch that turns spoken replies on.

import type { VoiceMediaPatch, VoiceMediaStatus } from './useVoiceMediaWire';
import { VoiceMediaCard } from './VoiceMediaCard';
import { IconVolume } from './voiceMediaIcons';

/** `_TtsSection._engineDisplayName`. */
export function ttsEngineName(engine: string | undefined): string {
  switch (engine) {
    case 'kokoro':
      return 'Kokoro TTS';
    case 'openai':
      return 'OpenAI TTS';
    case 'piper':
      return 'Piper TTS';
    default:
      return 'TTS';
  }
}

export function ttsSubtitle(s: VoiceMediaStatus): string {
  if (!s.ttsEnabled) return 'Disabled';
  const key = s.globalVoice ?? '';
  if (!key) return 'Enabled — Voice: Not set';
  const match = s.voices?.find((v) => v.id === key);
  return `Enabled — Voice: ${match ? match.name : key}`;
}

export function TtsCard({
  status,
  write,
}: {
  status: VoiceMediaStatus;
  write: (p: VoiceMediaPatch) => void;
}) {
  return (
    <VoiceMediaCard
      heading="Text-to-Speech"
      icon={<IconVolume />}
      title={ttsEngineName(status.ttsEngine)}
      subtitle={ttsSubtitle(status)}
      testid="vm-tts"
      control={
        <input
          type="checkbox"
          className="switch"
          aria-label="Enable text-to-speech"
          checked={status.ttsEnabled}
          onChange={(e) => write({ ttsEnabled: e.target.checked })}
        />
      }
    />
  );
}
