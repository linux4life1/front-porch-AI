// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director Mode on the web — the desktop sidebar's Director card and the
// exit UNDO SnackBar. Stepping out and back in run through the same
// `/director` commands as the desktop button, so the goodbye, the greeting
// and the UNDO all come from ChatService.

import { useEffect, useState } from 'react';
import { DirectorTools, type DirectorBeat, type DirectorWhisper } from './DirectorTools';

export interface DirectorState {
  directing: boolean;
  autoPlay: boolean;
  /** False while directing with two characters left: one more exit would
   *  end Director Mode. Absent on older apps. */
  canRemoveMember?: boolean;
  /** The auto-chat delay in seconds, sent while directing. Absent on older
   *  apps, which then show no delay control. */
  delaySeconds?: number | null;
  /** The director's tools. Absent on older apps, which then show none. */
  beats?: DirectorBeat[];
  goal?: string;
  whispers?: DirectorWhisper[];
  turnBudget?: number;
  /** Turns left in the running auto-chat, or null when unlimited. */
  turnsLeft?: number | null;
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
  onDelay,
  memberNames = [],
  onGoal,
  onClearWhisper,
  onTurnBudget,
}: {
  director: DirectorState;
  busy: boolean;
  onCommand: (cmd: string) => void;
  onAutoPlay: (on: boolean) => void;
  onDelay: (seconds: number) => void;
  memberNames?: string[];
  onGoal?: (text: string) => void;
  onClearWhisper?: (id: string) => void;
  onTurnBudget?: (turns: number) => void;
}) {
  const { directing, autoPlay, delaySeconds } = director;
  // The slider's live value while it is held; saved when it is let go.
  const [draft, setDraft] = useState<number | null>(null);
  const delay = draft ?? delaySeconds ?? null;
  const commit = () => {
    if (draft == null) return;
    onDelay(draft);
    setDraft(null);
  };
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
      {directing && delay != null && (
        <label className="director-delay">
          <span>Auto-chat delay</span>
          <input
            type="range"
            min={0.5}
            max={60}
            step={0.5}
            value={delay}
            aria-label="Auto-chat delay in seconds"
            onChange={(e) => setDraft(Number(e.target.value))}
            onPointerUp={commit}
            onKeyUp={commit}
            onBlur={commit}
          />
          <span className="director-delay-value">{delay.toFixed(1)}s</span>
        </label>
      )}
      {directing && director.beats && onGoal && onClearWhisper && onTurnBudget && (
        <DirectorTools
          memberNames={memberNames}
          beats={director.beats}
          goal={director.goal ?? ''}
          whispers={director.whispers ?? []}
          turnBudget={director.turnBudget ?? 0}
          turnsLeft={director.turnsLeft ?? null}
          busy={busy}
          onCommand={onCommand}
          onGoal={onGoal}
          onClearWhisper={onClearWhisper}
          onTurnBudget={onTurnBudget}
        />
      )}
    </div>
  );
}

export function ExitUndoBar({ undo, onUndo }: { undo: ExitUndo | null; onUndo: () => void }) {
  // Offered once per exit, for a few seconds, like the desktop SnackBar.
  const key = undo ? `${undo.isUser}:${undo.name}` : null;
  // Remembered for this tab, so a reload doesn't offer the same UNDO again.
  const [hidden, setHiddenState] = useState<string | null>(readHiddenUndo);
  const setHidden = (k: string | null) => {
    setHiddenState(k);
    writeHiddenUndo(k);
  };
  useEffect(() => {
    // A closed UNDO forgets what it hid, so the next exit by the same name
    // (or the next step out) is offered again.
    if (!key) {
      setHiddenState(null);
      writeHiddenUndo(null);
      return;
    }
    if (readHiddenUndo() === key) return;
    const t = setTimeout(() => {
      setHiddenState(key);
      writeHiddenUndo(key);
    }, UNDO_MS);
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

const HIDDEN_UNDO_KEY = 'fpai.exitUndoHidden';

function readHiddenUndo(): string | null {
  try {
    return sessionStorage.getItem(HIDDEN_UNDO_KEY);
  } catch {
    return null;
  }
}

function writeHiddenUndo(key: string | null) {
  try {
    if (key) sessionStorage.setItem(HIDDEN_UNDO_KEY, key);
    else sessionStorage.removeItem(HIDDEN_UNDO_KEY);
  } catch {
    // Storage blocked (private mode): the bar just isn't remembered.
  }
}
