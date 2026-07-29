// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Realism + lorebook + author-note insight panel (drawer on phone, sidebar on
// desktop). Extracted verbatim from ChatPage to keep that page under the
// file-size cap. Section order mirrors the desktop sidebar.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import { ChatLorebookModal } from './ChatLorebookModal';
import { ChatPlacesSection } from './ChatPlacesSection';
import { ChatTools } from './ChatTools';
import { type CastMember } from './CastBar';
import { LookSwiper } from './ChatAvatar';
import { type Realism, type LoreEntry, NEED_LABELS } from './chatTypes';

/**
 * "Does my model support tool calling?" pill — desktop sidebar parity.
 * Green = native tool calls work (Realism/Journal/Growth use them), amber =
 * text fallback, neutral = not tested yet. Click to retest the live model;
 * the server also retests automatically on model/backend switches.
 */
function ToolCallingPill({ support }: { support?: { state: string; testing: boolean } }) {
  const [busy, setBusy] = useState(false);
  const [local, setLocal] = useState(support);
  useEffect(() => setLocal(support), [support]);
  if (!local) return null;
  const testing = busy || local.testing;
  const s = local.state;
  const tone = testing ? 'busy' : s === 'supported' ? 'ok' : s === 'unsupported' ? 'warn' : 'idle';
  const label = testing
    ? 'Tool calling: testing…'
    : s === 'supported'
      ? 'Tool calling: supported'
      : s === 'unsupported'
        ? 'Tool calling: not supported'
        : 'Tool calling: not tested';
  const detail = testing
    ? 'Asking the model for a tool call'
    : s === 'supported'
      ? 'Realism, Journal & Growth use native tool calls'
      : s === 'unsupported'
        ? 'Using the text fallback — still works'
        : 'Click to test the current model';
  const retest = async () => {
    setBusy(true);
    try {
      setLocal(await api.post<{ state: string; testing: boolean }>('/api/chat/tool-test', {}));
    } catch {
      /* verdict refreshes with the next chat_updated anyway */
    }
    setBusy(false);
  };
  return (
    <button
      className={`tool-pill tool-pill-${tone}`}
      onClick={retest}
      disabled={testing}
      title="Whether the current model can answer engine evaluations (Realism, Journal, Growth Rings) with native tool calls. Without it a text fallback is used — chats still work. Click to retest; retests also run when you switch models."
    >
      <span className="tool-pill-dot" />
      <span className="tool-pill-text">
        <strong>{label}</strong>
        <span className="muted small">{detail}</span>
      </span>
      <span className="tool-pill-retest">↻</span>
    </button>
  );
}

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
  loreTokens,
  loreBudget,
  loreOverflow,
  draft,
  toolSupport,
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
  loreTokens?: number;
  loreBudget?: number;
  loreOverflow?: string[];
  /** Live composer draft — powers the "would trigger next" preview. */
  draft?: string;
  /** Current model's tool-calling verdict (POST /api/chat/tool-test retests). */
  toolSupport?: { state: string; testing: boolean };
}) {
  const [note, setNote] = useState(authorNote);
  // "Would trigger next": mutation-free dry-run against the draft, debounced.
  const [wouldTrigger, setWouldTrigger] = useState<string[]>([]);
  useEffect(() => {
    const text = (draft ?? '').trim();
    if (!text) {
      setWouldTrigger([]);
      return;
    }
    const t = setTimeout(() => {
      api
        .post<{ matches: string[] }>('/api/chat/lore-preview', { draft: text })
        .then((r) => setWouldTrigger(r.matches ?? []))
        .catch(() => setWouldTrigger([]));
    }, 400);
    return () => clearTimeout(t);
  }, [draft]);
  const [showChatBook, setShowChatBook] = useState(false);
  useEffect(() => setNote(authorNote), [authorNote]);
  // Author's Note strength (injection depth/weight, 1–10) — desktop parity.
  const [strength, setStrength] = useState(authorNoteDepth);
  useEffect(() => setStrength(authorNoteDepth), [authorNoteDepth]);
  return (
    <div className="realism-panel">
      <ToolCallingPill support={toolSupport} />
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
        <LookSwiper
          characterId={characterId}
          basePrimary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
          baseFallback={`/api/characters/${characterId}/avatar`}
          mood={realism.mood || realism.emotion}
        />
      ) : focusedAvatarUrl ? (
        <LookSwiper
          characterId={characterId}
          basePrimary={focusedAvatarUrl}
          mood={realism.mood || realism.emotion}
        />
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

      <ChatPlacesSection reloadKey={toolsKey} />

      <h4 className="section-label">Lorebook</h4>
      {typeof loreBudget === 'number' && loreBudget > 0 && (
        <div className={`lore-meter${(loreOverflow?.length ?? 0) > 0 ? ' over' : ''}`}>
          <div className="lore-meter-bar">
            <div
              style={{
                width: `${Math.min(100, Math.round(((loreTokens ?? 0) / loreBudget) * 100))}%`,
              }}
            />
          </div>
          <span>
            lore in prompt: {loreTokens ?? 0} / {loreBudget} tokens
            {(loreOverflow?.length ?? 0) > 0 ? ` — ${loreOverflow!.length} dropped` : ''}
          </span>
        </div>
      )}
      {lorebook && lorebook.length > 0 ? (
        <ul className="lore-list">
          {lorebook.map((e, i) => (
            <li
              key={i}
              className={`lore${e.isTriggered ? ' on' : ''}${e.constant ? ' const' : ''}`}
            >
              <span className="lore-dot" />
              <span>{e.name}{e.constant ? ' · always' : ''}</span>
              {(e.stickyLeft ?? 0) > 0 && (
                <span className="lore-pill ok">sticky {e.stickyLeft}</span>
              )}
              {(e.stickyLeft ?? 0) === 0 && (e.cooldownLeft ?? 0) > 0 && (
                <span className="lore-pill honey">cooldown {e.cooldownLeft}</span>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="muted small">No lorebook entries.</p>
      )}
      {wouldTrigger.length > 0 && (
        <div className="lore-preview">
          <span className="lore-preview-title">Would trigger next</span>
          <div className="lore-preview-chips">
            {wouldTrigger.slice(0, 6).map((n) => (
              <span key={n} className="lore-pill honey">{n}</span>
            ))}
            {wouldTrigger.length > 6 && (
              <span className="lore-pill honey">+{wouldTrigger.length - 6} more</span>
            )}
          </div>
        </div>
      )}
      <button className="ghost lore-chat-btn" onClick={() => setShowChatBook(true)}>
        Manage this chat's lore…
      </button>
      {showChatBook && <ChatLorebookModal onClose={() => setShowChatBook(false)} />}
    </div>
  );
}
