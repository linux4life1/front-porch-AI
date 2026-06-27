// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-character TTS voice picker for the bible dashboard cast. Binds each cast
// member's read-along voice (cast[].voice_model) to the host's active TTS voices
// — mirrors the desktop dashboard's Voice dropdown. Saved on change.

import type { StoryCastMember, StoryVoice } from '../../storyTypes';

export function CastVoiceEditor({
  cast, voices, onPick,
}: {
  cast: StoryCastMember[];
  voices: StoryVoice[];
  onPick: (index: number, voiceId: string) => void;
}) {
  return (
    <section className="card">
      <h3>Cast</h3>
      {voices.length === 0 && (
        <p className="muted small">Enable TTS to assign read-along voices.</p>
      )}
      {cast.map((c, i) => (
        <div key={i} className="cast-voice-row">
          <span className="cast-name">{c.name}</span>
          <span className="cast-role">{c.role}</span>
          {voices.length > 0 && (
            <select value={c.voice_model || ''} onChange={(e) => onPick(i, e.target.value)}>
              <option value="">Default narrator</option>
              {voices.map((v) => (
                <option key={v.id} value={v.id}>{v.name}</option>
              ))}
            </select>
          )}
        </div>
      ))}
      {cast.map((c, i) => c.description ? (
        <p key={`d${i}`} className="muted small" style={{ margin: '2px 0 6px' }}>
          <strong>{c.name}:</strong> {c.description}
        </p>
      ) : null)}
    </section>
  );
}
