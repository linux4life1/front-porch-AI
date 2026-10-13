// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The director's tools on the web — the desktop Director panel's
// DirectorTools twin: cue who speaks next, quick beats, the pinned scene
// goal, the private whispers, and how long an auto-chat run goes. Cues and
// beats send the same text the desktop sends (`/speak <name>`, the beat's
// note); the beats list itself comes from the app, so the two never drift.

import { useState } from 'react';

export interface DirectorBeat {
  label: string;
  note: string;
}

export interface DirectorWhisper {
  id: string;
  name: string;
  text: string;
}

/** The auto-chat run lengths offered (0 = no limit), as on the desktop. */
export const TURN_BUDGET_CHOICES = [0, 3, 6, 10, 20];

export function DirectorTools({
  memberNames,
  beats,
  goal,
  whispers,
  turnBudget,
  turnsLeft,
  busy,
  onCommand,
  onGoal,
  onClearWhisper,
  onTurnBudget,
}: {
  memberNames: string[];
  beats: DirectorBeat[];
  goal: string;
  whispers: DirectorWhisper[];
  turnBudget: number;
  turnsLeft: number | null;
  busy: boolean;
  onCommand: (text: string) => void;
  onGoal: (text: string) => void;
  onClearWhisper: (id: string) => void;
  onTurnBudget: (turns: number) => void;
}) {
  const [goalDraft, setGoalDraft] = useState('');
  const pinGoal = () => {
    const text = goalDraft.trim();
    if (!text) return;
    onGoal(text);
    setGoalDraft('');
  };
  return (
    <div className="director-tools">
      <div className="director-row" aria-label="Cue who speaks next">
        <span className="director-label">Cue</span>
        {memberNames.map((name) => (
          <button key={name} className="chip" disabled={busy} onClick={() => onCommand(`/speak ${name}`)}>
            {name}
          </button>
        ))}
      </div>
      <div className="director-row" aria-label="Quick beats">
        <span className="director-label">Beats</span>
        {beats.map((b) => (
          <button key={b.label} className="chip" disabled={busy} onClick={() => onCommand(b.note)}>
            ⚡ {b.label}
          </button>
        ))}
      </div>
      {goal ? (
        <div className="director-pinned" role="note">
          <span>📌 {goal}</span>
          <button className="ghost small" aria-label="Clear the scene goal" onClick={() => onGoal('')}>
            ✕
          </button>
        </div>
      ) : (
        <form
          className="director-row"
          onSubmit={(e) => {
            e.preventDefault();
            pinGoal();
          }}
        >
          <input
            className="director-goal-input"
            value={goalDraft}
            placeholder="Scene goal: where should the scene go?"
            aria-label="Scene goal"
            onChange={(e) => setGoalDraft(e.target.value)}
          />
          <button type="submit" className="ghost small" disabled={!goalDraft.trim()}>
            Pin
          </button>
        </form>
      )}
      {whispers.map((w) => (
        <div key={w.id} className="director-pinned" role="note">
          <span>
            🤫 {w.name}: {w.text}
          </span>
          <button className="ghost small" aria-label={`Clear the whisper to ${w.name}`} onClick={() => onClearWhisper(w.id)}>
            ✕
          </button>
        </div>
      ))}
      {whispers.length === 0 && (
        <span className="director-hint">/whisper &lt;name&gt; &lt;direction&gt; tells one character something the others don’t know.</span>
      )}
      <label className="director-row">
        <span className="director-label">Auto-chat run</span>
        <select
          value={TURN_BUDGET_CHOICES.includes(turnBudget) ? turnBudget : 0}
          aria-label="Auto-chat run length"
          onChange={(e) => onTurnBudget(Number(e.target.value))}
        >
          {TURN_BUDGET_CHOICES.map((n) => (
            <option key={n} value={n}>
              {n === 0 ? 'No limit' : `${n} turns`}
            </option>
          ))}
        </select>
        {turnsLeft != null && <span className="director-delay-value">{turnsLeft} left</span>}
      </label>
    </div>
  );
}
