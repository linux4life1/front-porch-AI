// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Whether a character's voice is playing on this device right now, so the
// scene sound can duck under it (docs/design/ambient-stage.md §5). The
// Speak button hands each voice clip it plays to trackVoice; anyone can
// listen with onVoiceActivity.

const playing = new Set<HTMLMediaElement>();
const listeners = new Set<(speaking: boolean) => void>();

function emit(): void {
  const speaking = playing.size > 0;
  for (const l of listeners) l(speaking);
}

/** Follows one voice clip from its first sound to its end, pause or failure. */
export function trackVoice(el: HTMLMediaElement): void {
  const start = () => {
    if (playing.has(el)) return;
    playing.add(el);
    emit();
  };
  const stop = () => {
    if (playing.delete(el)) emit();
  };
  el.addEventListener('playing', start);
  el.addEventListener('pause', stop);
  el.addEventListener('ended', stop);
  el.addEventListener('error', stop);
}

/** Whether any tracked voice clip is playing now. */
export function isVoicePlaying(): boolean {
  return playing.size > 0;
}

/** Calls back with true when a voice starts and false when the last one stops; returns the unsubscribe. */
export function onVoiceActivity(listener: (speaking: boolean) => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
