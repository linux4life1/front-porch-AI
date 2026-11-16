// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Realism + lorebook + author-note insight panel (drawer on phone, sidebar on
// desktop). Extracted verbatim from ChatPage to keep that page under the
// file-size cap. Section order mirrors the desktop sidebar.

import { useEffect, useState } from 'react';
import { api } from '../api/client';
import {
  SIDEBAR_DEFAULTS,
  SidebarGrip,
  SidebarLockPill,
  SidebarResetPill,
  resolveOrder,
  resetSidebarLayout,
  useReorderDrag,
  useSidebarOrder,
} from './sidebarReorder';
import { OneShotEvalControl } from './OneShotEvalControl';
import { ToolCallingPill, type ToolSupport } from './ToolCallingPill';
import { ChatLorebookModal } from './ChatLorebookModal';
import { ImportLorebookWizard } from './ImportLorebookWizard';
import { ChatPlacesSection } from './ChatPlacesSection';
import { ChatTools } from './ChatTools';
import { type CastMember } from './CastBar';
import { LookSwiper, Portrait } from './ChatAvatar';
import { type Realism, type LoreEntry, NEED_LABELS } from './chatTypes';
import { NeedBar, StatBar } from './StatBar';
import {
  firstNeedInTrouble, moodAtmosphereOf, moodVars, needTrouble, type MoodLook, type MoodPaints,
} from '../theme/moodAtmosphere';

/** Same words as the desktop sidebar's note. */
const GROUP_LOREBOOK_UNREADABLE_NOTE =
  "This group's lorebook couldn't be read, so its entries aren't being used. " +
  'Open Edit group, Lorebook tab, to bring it back.';

export function ChatInsight({
  realism,
  lorebook,
  groupLorebookUnreadable,
  authorNote,
  authorNoteDepth,
  onSaveAuthorNote,
  characterId,
  expressionLabel,
  isGroup,
  focusedIsHost,
  focusedIsLiteGuest,
  focusedAvatarUrl,
  focusedPlaceholderPortrait,
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
  moodLook,
  moodPaints,
}: {
  realism: Realism;
  /** Appearance → Mood on the character and the desktop's colours for it. */
  moodLook?: MoodLook;
  moodPaints?: MoodPaints | null;
  /** Focused cast member is a lightweight scene guest with no realism state. */
  focusedIsLiteGuest?: boolean;
  lorebook?: LoreEntry[];
  /** The group's stored lorebook could not be read — say so, as desktop does. */
  groupLorebookUnreadable?: boolean;
  authorNote: string;
  authorNoteDepth: number;
  onSaveAuthorNote: (note: string, strength: number) => void;
  characterId: string;
  expressionLabel?: string;
  isGroup: boolean;
  focusedIsHost: boolean;
  focusedAvatarUrl?: string;
  /** The focused character's picture is only the flat no-portrait colour. */
  focusedPlaceholderPortrait?: boolean;
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
  toolSupport?: ToolSupport;
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
  // Import Lorebook wizard entry (desktop "This Chat" sidebar download icon
  // parity — the Worlds tab no longer hosts this).
  const [showImportBook, setShowImportBook] = useState(false);
  const [importMsg, setImportMsg] = useState('');
  useEffect(() => setNote(authorNote), [authorNote]);
  // Author's Note strength (injection depth/weight, 1–10) — desktop parity.
  const [strength, setStrength] = useState(authorNoteDepth);
  useEffect(() => setStrength(authorNoteDepth), [authorNoteDepth]);
  // Mood on the character: the portrait's ring, halo and need rim, and the
  // needs bars' throb, from this character's own Realism state. Off while
  // the setting is off, the desktop sent no colours, or Realism is off here.
  const moodOn = (moodLook?.level ?? 'off') !== 'off' && !!moodPaints && realism.realismEnabled !== false;
  const enjoysLowHygiene = realism.enjoysLowHygiene === true;
  const needHue = moodOn && realism.needsEnabled
    ? (() => { const n = firstNeedInTrouble(realism.needs, enjoysLowHygiene); return n ? moodPaints!.needs[n] ?? null : null; })()
    : null;
  const atmosphere = moodAtmosphereOf(realism.emotion, realism.emotionIntensity, realism.emotionHeld, moodLook?.drama ?? 1);
  const moodStyle = moodOn ? moodVars(atmosphere, moodPaints!, realism.bond.score, realism.trust.level, needHue) : undefined;
  const moodClass = moodOn
    ? `mood-portrait on${atmosphere.tone ? ` tone-${atmosphere.tone}` : ''}${needHue ? ' need' : ''}`
    : 'mood-portrait';

  // The remembered order: read from the host snapshot, kept live across
  // `settings_changed`, and POSTed on a drag. The host merges ids hidden
  // right now back into their stored slots.
  const { stored, locked, commit, setLocked } = useSidebarOrder('insight');
  const visible = [
    'one_shot_eval',
    'tool_calling_pill',
    ...(isGroup && cast && cast.length > 1 && onFocus ? ['cast_chips'] : []),
    'portrait',
    'author_note',
    'realism_stats',
    'chat_tools',
    'places',
    'lorebook',
  ];
  const ordered = resolveOrder(stored, visible, SIDEBAR_DEFAULTS.insight);
  const { listEl, itemEls, dragId, startDrag, dragMove, endDrag } = useReorderDrag(
    ordered,
    commit,
    !locked,
  );

  const grip = (id: string) => (
    <SidebarGrip locked={locked} onDown={(e) => startDrag(e, id)} />
  );
  const section = (id: string) => {
    switch (id) {
      case 'one_shot_eval':
        return (
          <>
            {grip(id)}
            <OneShotEvalControl reloadKey={toolsKey} />
          </>
        );
      case 'tool_calling_pill':
        return (
          <>
            {grip(id)}
            <ToolCallingPill support={toolSupport} />
          </>
        );
      case 'cast_chips':
        return cast && onFocus ? (
          <>
            {grip(id)}
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
          </>
        ) : null;
      case 'portrait':
        return (
          <>
            {grip(id)}
            <div className={moodClass} style={moodStyle as React.CSSProperties | undefined} data-testid="mood-portrait" data-tone={atmosphere.tone ?? ''}>
              {isGroup ? (
                focusedId ? (
                  <Portrait
                    primary={`/api/chat/expression-avatar?participant=${encodeURIComponent(focusedId)}&v=${encodeURIComponent(realism.expressionLabel ?? '')}`}
                    fallback={focusedPlaceholderPortrait ? undefined : focusedAvatarUrl}
                    mood={realism.mood || realism.emotion}
                  />
                ) : null
              ) : focusedIsHost ? (
                <LookSwiper
                  characterId={characterId}
                  basePrimary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
                  baseFallback={
                    focusedPlaceholderPortrait ? undefined : `/api/characters/${characterId}/avatar`
                  }
                  mood={realism.mood || realism.emotion}
                />
              ) : focusedAvatarUrl && !focusedPlaceholderPortrait ? (
                <LookSwiper
                  characterId={characterId}
                  basePrimary={focusedAvatarUrl}
                  mood={realism.mood || realism.emotion}
                />
              ) : null}
            </div>
          </>
        );
      case 'author_note':
        return (
          <>
            {grip(id)}
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
          </>
        );
      case 'realism_stats':
        return (
          <>
            {grip(id)}
            {focusedIsLiteGuest ? (
              <p className="muted realism-off">
                Lite NPC — no realism or needs tracking for this guest.
              </p>
            ) : (
              <>
                {realism.realismEnabled === false ? (
                  <p className="muted realism-off">
                    {realism.realismAllowed === false
                      ? "The Realism Engine is off in Porch Life. This chat's own choice is kept."
                      : realism.realismSwitch === true
                        ? 'Realism starts again when this reply finishes.'
                        : 'The Realism Engine is off for this chat — flip the switch to track bond, trust, mood, and scene time for this character.'}
                  </p>
                ) : (
                  <>
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
                    {realism.lustOn === true && (
                      <div className="stat-line"><span>Lust</span><span className="muted">{realism.arousal.tier} · {realism.arousal.level}</span></div>
                    )}
                    {realism.lustOn === true && realism.refractoryLabel && (
                      <div className="stat-line"><span className="muted">{realism.refractoryLabel}</span></div>
                    )}
                  </>
                )}
                {realism.needsEnabled && Object.keys(realism.needs).length > 0 && (
                  <>
                    <h4 className="section-label">Needs</h4>
                    {Object.entries(realism.needs).map(([k, v]) => (
                      <NeedBar
                        key={k}
                        label={NEED_LABELS[k] ?? k}
                        value={v}
                        urgentAt={realism.needsUrgentAt}
                        criticalAt={realism.needsCriticalAt}
                        trouble={moodOn ? needTrouble(k, v, enjoysLowHygiene) : undefined}
                        hue={moodOn ? moodPaints!.needs[k] : undefined}
                      />
                    ))}
                  </>
                )}
              </>
            )}
          </>
        );
      case 'chat_tools':
        return (
          <>
            {grip(id)}
            <ChatTools reloadKey={toolsKey} focusedId={focusedId} groupId={groupId} onCommand={onCommand}
              cast={isGroup ? cast : undefined} />
          </>
        );
      case 'places':
        return (
          <>
            {grip(id)}
            <ChatPlacesSection reloadKey={toolsKey} />
          </>
        );
      case 'lorebook':
        return (
          <>
            {grip(id)}
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
            {groupLorebookUnreadable && (
              <p className="small lore-unreadable" role="status">
                {GROUP_LOREBOOK_UNREADABLE_NOTE}
              </p>
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
            <button className="ghost lore-chat-btn" onClick={() => setShowImportBook(true)}>
              Import a lorebook…
            </button>
            {importMsg && <p className="muted small">{importMsg}</p>}
            {showChatBook && <ChatLorebookModal onClose={() => setShowChatBook(false)} />}
            {showImportBook && (
              <ImportLorebookWizard
                onClose={() => setShowImportBook(false)}
                onImported={setImportMsg}
              />
            )}
          </>
        );
    }
    return null;
  };

  return (
    <div
      className="realism-panel"
      ref={listEl}
      onPointerMove={dragMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onLostPointerCapture={endDrag}
    >
      <div className="sidebar-layout-pills">
        <SidebarResetPill onReset={resetSidebarLayout} />
        <SidebarLockPill locked={locked} onToggle={() => setLocked(!locked)} />
      </div>
      {ordered.map((id) => (
        <div
          key={id}
          className={`insight-section${dragId === id ? ' dragging' : ''}`}
          data-id={id}
          ref={(el) => {
            if (el) itemEls.current.set(id, el);
            else itemEls.current.delete(id);
          }}
        >
          {section(id)}
        </div>
      ))}
    </div>
  );
}
