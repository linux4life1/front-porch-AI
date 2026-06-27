// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Realism + lorebook + author-note insight panel (drawer on phone, sidebar on
// desktop). Extracted verbatim from ChatPage to keep that page under the
// file-size cap. Section order mirrors the desktop sidebar.

import { useEffect, useState } from 'react';
import { ChatTools } from './ChatTools';
import { type CastMember } from './CastBar';
import { Portrait } from './ChatAvatar';
import { type Realism, type LoreEntry, NEED_LABELS } from './chatTypes';

/** A labelled stat bar (bond / trust / needs). */
function StatBar({ label, value, percent, tone }: { label: string; value: string; percent: number; tone?: string }) {
  const pct = Math.max(0, Math.min(100, percent <= 1 ? percent * 100 : percent));
  return (
    <div className="stat">
      <div className="stat-head">
        <span>{label}</span>
        <span className="muted">{value}</span>
      </div>
      <div className="stat-track">
        <div className={`stat-fill ${tone ?? ''}`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export function ChatInsight({
  realism,
  lorebook,
  authorNote,
  authorNoteDepth,
  onSaveAuthorNote,
  characterId,
  expressionLabel,
  isGroup,
  focusedIsHost,
  focusedAvatarUrl,
  toolsKey,
  focusedId,
  groupId,
  onCommand,
  cast,
  onFocus,
}: {
  realism: Realism;
  lorebook?: LoreEntry[];
  authorNote: string;
  authorNoteDepth: number;
  onSaveAuthorNote: (note: string, strength: number) => void;
  characterId: string;
  expressionLabel?: string;
  isGroup: boolean;
  focusedIsHost: boolean;
  focusedAvatarUrl?: string;
  toolsKey: number;
  focusedId: string | null;
  groupId: string | null;
  onCommand: (cmd: string) => void;
  cast?: CastMember[];
  onFocus?: (id: string) => void;
}) {
  const [note, setNote] = useState(authorNote);
  useEffect(() => setNote(authorNote), [authorNote]);
  // Author's Note strength (injection depth/weight, 1–10) — desktop parity.
  const [strength, setStrength] = useState(authorNoteDepth);
  useEffect(() => setStrength(authorNoteDepth), [authorNoteDepth]);
  return (
    <div className="realism-panel">
      {/* Group: switch which member's stats you're viewing (the cast bar is
          covered by this panel on phone, so the switcher lives here too). */}
      {isGroup && cast && cast.length > 1 && onFocus && (
        <div className="insight-cast">
          {cast.map((c) => (
            <button
              key={c.id}
              className={`insight-cast-chip${c.id === focusedId ? ' active' : ''}`}
              onClick={() => onFocus(c.id)}
            >
              {c.name}
            </button>
          ))}
        </div>
      )}
      {/* Mood-expression portrait for the 1:1 host (and 1:1 scene guests). NOT
          shown in groups — member avatars don't resolve, so we'd only get a
          broken image. Hidden on phones too via CSS ([data-layout="phone"]
          .portrait-wrap). Self-hides if its image fails. */}
      {isGroup ? null : focusedIsHost ? (
        <Portrait
          primary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
          fallback={`/api/characters/${characterId}/avatar`}
          mood={realism.mood || realism.emotion}
        />
      ) : focusedAvatarUrl ? (
        <Portrait primary={focusedAvatarUrl} mood={realism.mood || realism.emotion} />
      ) : null}

      {/* Author's note sits near the top (matches the desktop sidebar order). */}
      <h4 className="section-label">Author's note</h4>
      <textarea
        className="note-input"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Steer the narrative (injected near the end of context)…"
        rows={3}
      />
      <label className="row-label note-strength">
        <span>Strength: {strength}</span>
        <input
          type="range"
          min={1}
          max={10}
          step={1}
          value={strength}
          onChange={(e) => setStrength(Number(e.target.value))}
        />
      </label>
      <button className="primary note-save" onClick={() => onSaveAuthorNote(note, strength)}>
        Save note
      </button>

      {/* Current fixation, highlighted, just above the realism stats (desktop order). */}
      {realism.fixation && (
        <div className="stat-fixation">
          <span className="fixation-label">Current fixation</span> {realism.fixation}
        </div>
      )}
      <StatBar label="Bond" value={`${realism.bond.tier} · ${realism.bond.score}`} percent={realism.bond.percent} />
      <StatBar label="Long-term" value={`${realism.longTerm.tier} · ${realism.longTerm.score}`} percent={realism.longTerm.percent} />
      <StatBar
        label="Trust"
        value={`${realism.trust.tier} · ${realism.trust.level}`}
        percent={realism.trust.percent}
        tone={realism.trust.level < 0 ? 'danger' : ''}
      />
      <div className="stat-line"><span>Mood</span><span className="muted">{realism.mood || realism.emotion || '—'}</span></div>
      <div className="stat-line"><span>Arousal</span><span className="muted">{realism.arousal.tier} · {realism.arousal.level}</span></div>
      {realism.needsEnabled && Object.keys(realism.needs).length > 0 && (
        <>
          <h4 className="section-label">Needs</h4>
          {Object.entries(realism.needs).map(([k, v]) => (
            <StatBar key={k} label={NEED_LABELS[k] ?? k} value={`${v}`} percent={v}
              tone={v <= 20 ? 'danger' : ''} />
          ))}
        </>
      )}

      <ChatTools reloadKey={toolsKey} focusedId={focusedId} groupId={groupId} onCommand={onCommand} />

      {lorebook && lorebook.length > 0 && (
        <>
          <h4 className="section-label">Lorebook</h4>
          <ul className="lore-list">
            {lorebook.map((e, i) => (
              <li key={i} className={e.isTriggered ? 'lore on' : 'lore'}>
                <span className="lore-dot" />
                <span>{e.name}{e.constant ? ' · always' : ''}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
