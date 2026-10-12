// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director Mode on the web — the desktop sidebar's Director card and the
// exit UNDO SnackBar. Stepping out and back in run through the same
// `/director` commands as the desktop button, so the goodbye, the greeting
// and the UNDO all come from ChatService.

import { useEffect, useState } from 'react';

export interface DirectorState {
  directing: boolean;
  autoPlay: boolean;
  /** False while directing with two characters left: one more exit would
   *  end Director Mode. Absent on older apps. */
  canRemoveMember?: boolean;
}

export interface ExitUndo {
  name: string;
  /** The user's own step out to direct, not a character leaving. */
  isUser: boolean;
}

/** Who the director note card is from: `ChatMessage.characterId`. */
export const DIRECTOR_CHARACTER_ID = '__director__';

/** How long the UNDO stays offered, as on the desktop. */
const UNDO_MS = 8000;

export function DirectorStrip({
  director,
  busy,
  onCommand,
  onAutoPlay,
}: {
  director: DirectorState;
  busy: boolean;
  onCommand: (cmd: string) => void;
  onAutoPlay: (on: boolean) => void;
}) {
  const { directing, autoPlay } = director;
  return (
    <div className={`director-strip${directing ? ' directing' : ''}`}>
      <span className="director-status">
        🎬 {directing ? 'You’re directing' : 'You’re in the scene'}
      </span>
      {directing && (
        <button
          className="ghost small"
          onClick={() => onAutoPlay(!autoPlay)}
          title={autoPlay ? 'Pause auto-chat' : 'Let the cast keep talking on their own'}
        >
          {autoPlay ? '⏸ Pause auto-chat' : '▶ Auto-chat'}
        </button>
      )}
      <button
        className="ghost small"
        disabled={busy}
        onClick={() => onCommand(directing ? '/director off' : '/director')}
        title={
          directing
            ? 'Walk back into the scene; a character greets you'
            : 'Leave the scene to direct it; the cast keeps talking'
        }
      >
        {directing ? 'Step back in' : 'Step out to direct'}
      </button>
    </div>
  );
}

export function ExitUndoBar({ undo, onUndo }: { undo: ExitUndo | null; onUndo: () => void }) {
  // Offered once per exit, for a few seconds, like the desktop SnackBar.
  const key = undo ? `${undo.isUser}:${undo.name}` : null;
  const [hidden, setHidden] = useState<string | null>(null);
  useEffect(() => {
    if (!key) return;
    const t = setTimeout(() => setHidden(key), UNDO_MS);
    return () => clearTimeout(t);
  }, [key]);
  if (!undo || hidden === key) return null;
  return (
    <div className="undo-bar" role="status">
      <span>{undo.isUser ? 'You stepped out to direct' : `${undo.name} left the scene`}</span>
      <button
        className="ghost small"
        onClick={() => {
          setHidden(key);
          onUndo();
        }}
      >
        Undo
      </button>
    </div>
  );
}
