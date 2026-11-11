// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat sidebar — the desktop window's right column (PR 1a), and the same
// card tree in the drawer below 1024 (PR 1b). Portrait, Main Settings, the
// layout pills, then the cast, Director, and the tool cards. The tools
// snapshot plumbing (focus scoping, embedding poll, mutation helpers)
// mirrors ChatTools.tsx so both surfaces speak to the same endpoints with the
// same payloads.

import { ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import {
  SidebarGrip,
  SidebarLockPill,
  SidebarResetPill,
  resolveOrder,
  resetSidebarLayout,
  useReorderDrag,
} from './sidebarReorder';
import { OneShotEvalControl } from './OneShotEvalControl';
import { ToolCallingPill, type ToolSupport } from './ToolCallingPill';
import { ChatLorebookModal } from './ChatLorebookModal';
import { ImportLorebookWizard } from './ImportLorebookWizard';
import { ChatPlacesSection } from './ChatPlacesSection';
import { LookSwiper, Portrait } from './ChatAvatar';
import { CardMenu, type CardMenuItem } from './library/CardMenu';
import { GroupSettings } from './GroupSettings';
import { BelongingsPanel } from './BelongingsPanel';
import { PromisesPanel } from './PromisesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';
import {
  ChatToolsMemory, ChatToolsRecap, ChatToolsWiki,
} from './ChatToolsMemory';
import { ChatToolsChaos } from './ChatToolsRealism';
import { PocketAddRow } from './PocketAddRow';
import { ChatToolsObjectives } from './ChatToolsObjectives';
import { type ToolsState } from './ChatToolsShared';
import { type Realism, type LoreEntry, NEED_LABELS } from './chatTypes';
import { NeedBar, StatBar } from './StatBar';
import {
  firstNeedInTrouble, moodAtmosphereOf, moodVars, needTrouble, type MoodLook, type MoodPaints,
} from '../theme/moodAtmosphere';

/** Same words as the desktop sidebar's note (kept in lock-step with
 *  ChatInsight's copy). */
const GROUP_LOREBOOK_UNREADABLE_NOTE =
  "This group's lorebook couldn't be read, so its entries aren't being used. " +
  'Open Group Settings, Lorebook & Worlds, on the computer to bring it back.';

/** Scene-time period dots — the same table ChatTools renders (mirror the
 *  desktop realism_section _timeDotLabel: D / M / LM / A / E / N). */
const TIME_DOTS: [string, string][] = [
  ['dawn', 'D'],
  ['morning', 'M'],
  ['late_morning', 'LM'],
  ['afternoon', 'A'],
  ['evening', 'E'],
  ['night', 'N'],
];

/** Each need's own hue, as the window paints it — the tokens the desktop
 *  resolves per mode (WebThemeTokens._realism). Unknown keys fall back to
 *  the level tone. */
const NEED_TOKENS: Record<string, string> = {
  hunger: 'var(--need-hunger)',
  bladder: 'var(--need-bladder)',
  energy: 'var(--need-energy)',
  social: 'var(--need-social)',
  fun: 'var(--need-fun)',
  hygiene: 'var(--need-hygiene)',
  comfort: 'var(--need-comfort)',
};

/** The reorderable cards' shipped default, after the static portrait +
 *  Main Settings + pills header. Matches the target's card order. */
const WIDE_DEFAULTS = [
  'cast',
  'director',
  'one_shot_eval',
  'tool_calling_pill',
  'author_note',
  'wiki',
  'character_state',
  'journal_memory',
  'objectives',
  'story_tools',
];

export function ChatSidebar({
  realism,
  moodLook,
  moodPaints,
  focusedIsLiteGuest,
  lorebook,
  groupLorebookUnreadable,
  authorNote,
  authorNoteDepth,
  onSaveAuthorNote,
  characterId,
  expressionLabel,
  isGroup,
  focusedIsHost,
  focusedAvatarUrl,
  focusedPlaceholderPortrait,
  toolsKey,
  focusedId,
  groupId,
  onCommand,
  loreTokens,
  loreBudget,
  loreOverflow,
  draft,
  toolSupport,
  castBar,
  focusedName,
  portraitName,
  director,
  onEditCharacter,
  onChatSettings,
  onOpenOverlay,
  onModelSettings,
}: {
  realism: Realism;
  moodLook?: MoodLook;
  moodPaints?: MoodPaints | null;
  focusedIsLiteGuest?: boolean;
  lorebook?: LoreEntry[];
  groupLorebookUnreadable?: boolean;
  authorNote: string;
  authorNoteDepth: number;
  onSaveAuthorNote: (note: string, strength: number) => void;
  characterId: string;
  expressionLabel?: string;
  isGroup: boolean;
  focusedIsHost: boolean;
  focusedAvatarUrl?: string;
  focusedPlaceholderPortrait?: boolean;
  toolsKey: number;
  focusedId: string | null;
  groupId: string | null;
  onCommand: (cmd: string) => void;
  loreTokens?: number;
  loreBudget?: number;
  loreOverflow?: string[];
  draft?: string;
  toolSupport?: ToolSupport;
  /** The CastBar element the page assembled (moved here on wide, PR 1a). */
  castBar?: ReactNode;
  /** Director as the card's subtitle prefix, as the group target shows
   *  ("Vivian · Warming · Trusting · Evening"); absent in a plain 1:1. */
  focusedName?: string;
  /** Name for the portrait's initial square — what the window draws when
   *  the character has no real portrait. */
  portraitName?: string;
  /** The DirectorStrip element, same move. */
  director?: ReactNode;
  /** Absent when there is no library character to edit. */
  onEditCharacter?: () => void;
  /** Opens today's Chat settings drawer (Prompt source + Generation + theme). */
  onChatSettings: () => void;
  /** A Main Settings item is opening its own dialog: the phone/tablet
   *  drawer steps aside first, so closing the dialog lands back on the chat
   *  (PR 1b). Harmless at ≥1024, where the sidebar is a column. */
  onOpenOverlay?: () => void;
  /** Opens the page-level Change model sheet (it lives outside the drawer so
   *  closing the drawer cannot hide it). */
  onModelSettings?: () => void;
}) {
  // ── Tools snapshot (same plumbing as ChatTools.tsx) ──────────────────
  const [t, setT] = useState<ToolsState | null>(null);
  const [showCalendar, setShowCalendar] = useState(false);
  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';
  const load = useCallback(async () => {
    try {
      setT(await api.get<ToolsState>(`/api/chat/tools${q}`));
    } catch {
      /* no active chat / not wired — cards needing it stay hidden */
    }
  }, [q]);
  useEffect(() => {
    void load();
  }, [load, toolsKey]);
  // While the host downloads the embedding model, poll so the bar moves
  // (same 1s rule ChatTools uses).
  const embeddingBusy = Boolean(t?.memory?.ragEnabled && t?.memory?.embedding?.settingUp);
  useEffect(() => {
    if (!embeddingBusy) return;
    const id = window.setInterval(() => {
      void load();
    }, 1000);
    return () => window.clearInterval(id);
  }, [embeddingBusy, load]);
  const apply = (p: Promise<unknown>) => {
    void (p as Promise<ToolsState>).then(setT).catch(() => {});
  };
  const settings = (fields: Record<string, unknown>) =>
    apply(api.post<ToolsState>(`/api/chat/tools/settings${q}`, fields));
  const toggle = (name: string, value: boolean, extra?: Record<string, unknown>) =>
    apply(api.post<ToolsState>(`/api/chat/tools/toggle${q}`, { name, value, ...extra }));
  const pocketRemove = (section: string, index: number) =>
    apply(api.post<ToolsState>(`/api/chat/tools/pocket-remove${q}`, { section, index }));
  const pocketAdd = (section: string, name: string, gift: boolean, correction = false) =>
    apply(api.post<ToolsState>(`/api/chat/tools/pocket-add${q}`, { section, name, gift, correction }));
  const clockRunning = t?.time.clockRunning ?? false;
  // The Pockets line's stored switch (the chat's own choice; Porch Life's
  // veto greys it without changing it) and its "name (state)" item label.
  // In a group the Realism, Needs and Afterglow switches are the focused
  // member's own, for this chat: they route at the member toggles with
  // their id. A 1:1 (or a guest) has the chat's one switch.
  const memberId = t?.memberId ?? null;
  const switchToggle = (kind: 'Realism' | 'Needs' | 'Afterglow', fallback: string, v: boolean) =>
    memberId ? toggle(`member${kind}`, v, { id: memberId }) : toggle(fallback, v);
  const pocketsOn = typeof t?.pocketsSwitch === 'boolean' ? t.pocketsSwitch : true;
  const pocketLabel = (i: { name: string; state?: string }) =>
    i.state ? `${i.name} (${i.state})` : i.name;

  // Realism off for this chat (a group member comes back with no scores at
  // all, so nothing below may read them).
  const realismOff = realism.realismEnabled === false;

  // ── Portrait mood (same computation as ChatInsight) ──────────────────
  const moodOn =
    (moodLook?.level ?? 'off') !== 'off' && !!moodPaints && realism.realismEnabled !== false;
  const enjoysLowHygiene = realism.enjoysLowHygiene === true;
  const needHue =
    moodOn && realism.needsEnabled
      ? (() => {
          const n = firstNeedInTrouble(realism.needs, enjoysLowHygiene);
          return n ? moodPaints!.needs[n] ?? null : null;
        })()
      : null;
  const atmosphere = moodAtmosphereOf(
    realism.emotion,
    realism.emotionIntensity,
    realism.emotionHeld,
    moodLook?.drama ?? 1,
  );
  const moodStyle = moodOn
    ? moodVars(atmosphere, moodPaints!, realism.bond.score, realism.trust.level, needHue)
    : undefined;
  const moodClass = moodOn
    ? `mood-portrait on${atmosphere.tone ? ` tone-${atmosphere.tone}` : ''}${needHue ? ' need' : ''}`
    : 'mood-portrait';

  // ── Author's note (same controls and copy as ChatInsight) ────────────
  const [note, setNote] = useState(authorNote);
  // The window keeps Character State open; a wide card starts open too.
  const [stateOpen, setStateOpen] = useState(true);
  useEffect(() => setNote(authorNote), [authorNote]);
  const [strength, setStrength] = useState(authorNoteDepth);
  useEffect(() => setStrength(authorNoteDepth), [authorNoteDepth]);

  // ── Lorebook preview + modals (same as ChatInsight's lorebook case) ──
  const [wouldTrigger, setWouldTrigger] = useState<string[]>([]);
  useEffect(() => {
    const text = (draft ?? '').trim();
    if (!text) {
      setWouldTrigger([]);
      return;
    }
    const timer = setTimeout(() => {
      api
        .post<{ matches: string[] }>('/api/chat/lore-preview', { draft: text })
        .then((r) => setWouldTrigger(r.matches ?? []))
        .catch(() => setWouldTrigger([]));
    }, 400);
    return () => clearTimeout(timer);
  }, [draft]);
  const [showChatBook, setShowChatBook] = useState(false);
  const [showImportBook, setShowImportBook] = useState(false);
  const [importMsg, setImportMsg] = useState('');

  // ── Main Settings menu ────────────────────────────────────────────────
  const [settingsMenu, setSettingsMenu] = useState<{ x: number; y: number; items: CardMenuItem[] } | null>(null);
  const settingsBtnRef = useRef<HTMLButtonElement>(null);
  const [showGroupSettings, setShowGroupSettings] = useState(false);

  // ── Reorder (one order for every width) ──────────────────────────────
  // The host 'insight' surface still carries the OLD flat-panel ids, and
  // POSTing this tree's order there would drag that legacy list with it. So
  // the card tree persists its arrangement locally; phone and PC in one
  // browser profile share it (PR 1b), and the pills keep the same names.
  const ORDER_KEY = 'fpai.wideSidebarOrder';
  const LOCK_KEY = 'fpai.wideSidebarLocked';
  const [storedWide, setStoredWide] = useState<string[]>(() => {
    try {
      const raw = typeof localStorage !== 'undefined' ? localStorage.getItem(ORDER_KEY) : null;
      const parsed = raw ? JSON.parse(raw) : null;
      return Array.isArray(parsed) ? parsed.filter((x) => typeof x === 'string') : [];
    } catch {
      return [];
    }
  });
  const [locked, setLockedState] = useState<boolean>(() => {
    try {
      return typeof localStorage !== 'undefined' && localStorage.getItem(LOCK_KEY) === '1';
    } catch {
      return false;
    }
  });
  const commit = (ids: string[]) => {
    setStoredWide(ids);
    try {
      localStorage.setItem(ORDER_KEY, JSON.stringify(ids));
    } catch {
      /* private mode — the order just won't survive a reload */
    }
  };
  const setLocked = (v: boolean) => {
    setLockedState(v);
    try {
      localStorage.setItem(LOCK_KEY, v ? '1' : '0');
    } catch {
      /* ignore */
    }
  };
  const wideReset = () => {
    commit([]);
    try {
      localStorage.removeItem(ORDER_KEY);
    } catch {
      /* ignore */
    }
    resetSidebarLayout();
  };
  const visible = WIDE_DEFAULTS.filter((id) =>
    id === 'cast' ? !!castBar : id === 'director' ? !!director : true,
  );
  const ordered = resolveOrder(storedWide, visible, WIDE_DEFAULTS);
  const { listEl, itemEls, dragId, startDrag, dragMove, endDrag } = useReorderDrag(
    ordered,
    commit,
    !locked,
  );
  const grip = (id: string) => (
    <SidebarGrip wide locked={locked} onDown={(e) => startDrag(e, id)} />
  );

  const openSettingsMenu = () => {
    const r = settingsBtnRef.current?.getBoundingClientRect();
    const items: import('./library/CardMenu').CardMenuItem[] = [
      ...(onEditCharacter ? [{ label: 'Edit Character', onClick: onEditCharacter }] : []),
      { label: 'Chat Settings', onClick: () => { onOpenOverlay?.(); onChatSettings(); } },
      { label: 'Model Settings', onClick: () => { onOpenOverlay?.(); onModelSettings?.(); } },
      ...(t?.group && groupId
        ? [{ label: 'Group Settings…', onClick: () => setShowGroupSettings(true) }]
        : []),
    ];
    setSettingsMenu({
      x: Math.max(8, (r?.left ?? 8)),
      y: (r?.bottom ?? 40) + 4,
      items,
    });
  };

  const card = (id: string, node: ReactNode) => (
    <div
      className={`insight-section${dragId === id ? ' dragging' : ''}`}
      data-id={id}
      ref={(el) => {
        if (el) itemEls.current.set(id, el);
        else itemEls.current.delete(id);
      }}
    >
      {grip(id)}
      {node}
    </div>
  );

  const section = (id: string) => {
    switch (id) {
      case 'cast':
        return castBar;
      case 'director':
        return director ? (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>🎬 Director</summary>
            <div className="tool-body">{director}</div>
          </details>
        ) : null;
      case 'one_shot_eval':
        return <OneShotEvalControl reloadKey={toolsKey} />;
      case 'tool_calling_pill':
        return <ToolCallingPill support={toolSupport} />;
      case 'author_note':
        return (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>📝 Author's Note{' '}
              <span className="card-sub">strength {strength}</span></summary>
            <div className="tool-body">
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
            </div>
          </details>
        );
      case 'wiki':
        return t ? (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>📖 Wiki{' '}
              <span className="card-sub">{t.wikiBaseUrl ? 'on' : 'off'}</span>
            </summary>
            <div className="tool-body">
              <ChatToolsWiki t={t} q={q} apply={apply} />
            </div>
          </details>
        ) : null;
      case 'character_state':
        // Group Dynamics rides under Character State, as on the window: it
        // moves with it, so it always sits directly below.
        return (
          <>
          <details
            className="tool-section state-card"
            open={stateOpen}
            onToggle={(e) => setStateOpen(e.currentTarget.open)}
          >
            <summary><span className="card-chev" aria-hidden>❯</span>
              <span className="card-head-text">
                <span className="card-title">🎭 Character State</span>{' '}
                <span className="card-sub">
                  {[
                    focusedName,
                    realismOff ? undefined : realism.bond.tier,
                    realismOff ? undefined : realism.trust.tier,
                    t ? t.time.timeOfDay.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase()) : '',
                  ].filter(Boolean).join(' · ')}
                </span>
              </span>
              {/* The window keeps the Realism engine switch in the header: the chat's
                  in a 1:1, the focused member's own in a group.
                  Stopping the click/key keeps it from toggling the card. */}
              {t && (!isGroup || memberId) && (
                <label
                  className="card-switch"
                  onClick={(e) => e.stopPropagation()}
                  onKeyDown={(e) => e.stopPropagation()}
                >
                  <input
                    type="checkbox"
                    aria-label="Realism engine"
                    checked={t.realismSwitch ?? t.realismEnabled}
                    disabled={t.realismAllowed === false}
                    onChange={(e) => switchToggle('Realism', 'realism', e.target.checked)}
                  />
                </label>
              )}
            </summary>
            <div className="tool-body state-body">
              {t?.realismAllowed === false && (
                <p className="muted small">
                  The Realism Engine is off in Porch Life, so no chat runs it. This
                  chat&apos;s own choice is kept.
                </p>
              )}
              {focusedIsLiteGuest ? (
                <p className="muted realism-off">
                  Lite NPC — no realism or needs tracking for this guest.
                </p>
              ) : (
                <>
                  {realismOff && (
                    <p className="muted small realism-off">
                      {realism.realismAllowed === false
                        ? "The Realism Engine is off in Porch Life. This chat's own choice is kept."
                        : isGroup
                          ? `The Realism Engine is off for ${focusedName ?? 'this character'} in this chat — flip ` +
                            'the switch to track bond, trust, mood, and scene time for them.'
                          : realism.realismSwitch === true
                            ? 'Realism starts again when this reply finishes.'
                            : 'The Realism Engine is off for this chat — flip the switch to track bond, ' +
                              'trust, mood, and scene time for this character.'}
                    </p>
                  )}
                  {/* The window's order: bonds, Afterglow/Lust, fixation,
                      Needs and its bars, ambitions, Pockets, time. */}
                  {!realismOff && (
                  <>
                  <StatBar
                    label="Short-Term Bond"
                    value={`${realism.bond.tier} · ${realism.bond.score}`}
                    percent={realism.bond.percent}
                  />
                  <StatBar
                    label="Long-Term Bond"
                    value={`${realism.longTerm.tier} · ${realism.longTerm.score}`}
                    percent={realism.longTerm.percent}
                  />
                  <StatBar
                    label="Trust"
                    value={`${realism.trust.tier} · ${realism.trust.level}`}
                    percent={realism.trust.percent}
                    tone={realism.trust.level < 0 ? 'danger' : ''}
                    // The window paints Trust amber (trustAccentOf).
                    fill={realism.trust.level < 0 ? undefined : 'var(--accent-amber)'}
                  />
                  {t && t.realismEnabled && (t.nsfw.afterglowAllowed || t.nsfw.cooldownEnabled) && (
                    <>
                      {t.nsfw.afterglowAllowed && (
                        <label className="state-line">
                          <span>💗 Afterglow</span>
                          <input
                            type="checkbox"
                                    aria-label="Afterglow"
                            className="state-switch"
                            checked={t.nsfw.afterglowSwitch ?? t.nsfw.cooldownEnabled}
                            onChange={(e) => switchToggle('Afterglow', 'nsfwCooldown', e.target.checked)}
                          />
                        </label>
                      )}
                      {t.nsfw.cooldownEnabled && (
                        <StatBar
                          label={`Lust: ${t.nsfw.arousalTier}`}
                          value={`${t.nsfw.arousalLevel}/100`}
                          percent={Math.abs(t.nsfw.arousalLevel) / 100}
                          className="lust-bar"
                        />
                      )}
                      {t.nsfw.cooldownEnabled && t.nsfw.refractoryMinutesRemaining > 0 && (
                        <div className="stat-line">
                          <span className="muted">{t.nsfw.refractoryLabel}</span>
                        </div>
                      )}
                    </>
                  )}
                  {realism.fixation && (
                    <div className="stat-fixation">
                      <span className="fixation-label">Fixation</span> {realism.fixation}
                    </div>
                  )}
                  {(isGroup || t?.needsEnabled) && (
                    <>
                      {isGroup && !memberId ? (
                        // A guest carries no Needs of its own: the heading alone.
                        <div className="state-line">
                          <span>💗 Needs</span>
                        </div>
                      ) : (
                      <label className="state-line">
                        <span>💗 Needs</span>
                        <input
                          type="checkbox"
                                aria-label="Needs"
                          className="state-switch"
                          checked={t!.needsEnabled}
                          disabled={t!.needsAllowed === false}
                          onChange={(e) => switchToggle('Needs', 'needs', e.target.checked)}
                        />
                      </label>
                      )}
                      {t?.needsAllowed === false && (
                        <p className="muted small">
                          Off in Porch Life, so no chat runs Needs. This chat&apos;s choice is kept.
                        </p>
                      )}
                      {realism.needsEnabled &&
                        Object.entries(realism.needs).map(([k, v]) => (
                          <NeedBar
                            key={k}
                            label={NEED_LABELS[k] ?? k}
                            value={v}
                            urgentAt={realism.needsUrgentAt}
                            criticalAt={realism.needsCriticalAt}
                            trouble={moodOn ? needTrouble(k, v, enjoysLowHygiene) : undefined}
                            hue={moodOn ? moodPaints!.needs[k] : undefined}
                            fill={NEED_TOKENS[k]}
                          />
                        ))}
                    </>
                  )}
                  </>
                  )}
                  {t && (t.ambitions?.length ?? 0) > 0 && (
                    <div className="state-ambitions">
                      {t.ambitions!.map((a, i) => (
                        <div key={i} className="ambition-row" title={`${a.text} — ${a.stage}`}>
                          <div className="ambition-line">
                            <span className="ambition-pct">{Math.round(a.progress)}%</span>
                            <span>{a.text}</span>
                            <em className="ambition-stage">{a.stage}</em>
                          </div>
                          <div className="ambition-bar">
                            <div
                              className="ambition-bar-fill"
                              style={{ width: `${Math.min(100, Math.max(0, a.progress))}%` }}
                            />
                          </div>
                          {a.step?.trim() && <div className="ambition-step">↳ {a.step.trim()}</div>}
                        </div>
                      ))}
                    </div>
                  )}
                  {t && (t.pockets || typeof t.pocketsSwitch === 'boolean') && (
                    <div className="state-pockets">
                      <label className="state-line">
                        <span>🎒 Pockets &amp; Wardrobe</span>
                        <input
                          type="checkbox"
                                aria-label="Pockets &amp; Wardrobe"
                          className="state-switch"
                          checked={pocketsOn}
                          disabled={t.pocketsAllowed === false}
                          onChange={(e) => {
                            const on = e.target.checked;
                            if (!on) {
                              const who = (t.pocketsName ?? 'your character').trim() || 'your character';
                              const ok = window.confirm(
                                `Turn off Pockets & Wardrobe for ${who}? There is no catch-up ` +
                                  'mechanic implemented. If you turn this off, their current ' +
                                  'inventory and wardrobe will be retained but no longer ' +
                                  'tracked — changes in the chat will not be reflected when you ' +
                                  'turn it back on. Are you sure you want to do this?',
                              );
                              if (!ok) return;
                            }
                            toggle(
                              t.pocketsMemberId ? 'memberPockets' : 'pockets',
                              on,
                              t.pocketsMemberId ? { id: t.pocketsMemberId } : undefined,
                            );
                          }}
                        />
                      </label>
                      {t.pocketsAllowed === false && (
                        <div className="muted small">
                          Off in Porch Life, so no chat tracks pockets. This chat&apos;s choice is kept.
                        </div>
                      )}
                      {t.pocketsAllowed !== false && !pocketsOn && (
                        <div className="muted small">
                          {(t.pocketsName ?? 'your character').trim() || 'Your character'}&apos;s
                          inventory is retained, not tracked. Turn it back on to follow the
                          story again.
                        </div>
                      )}
                      {t.pockets && pocketsOn && (
                        <>
                          <div className="muted small side-quest-label">Wearing</div>
                          <div className="pocket-items">
                            {(t.pockets.worn ?? []).length === 0 ? (
                              <span className="pocket-empty">Put clothes on</span>
                            ) : (
                              (t.pockets.worn ?? []).map((i, n) => (
                                <span className="pocket-item" key={`w${n}`}>
                                  {pocketLabel(i)}
                                  <button
                                    className="pocket-x"
                                    title="Remove from the record"
                                    onClick={() => pocketRemove('worn', n)}
                                  >
                                    ×
                                  </button>
                                </span>
                              ))
                            )}
                          </div>
                          {(t.pockets.carrying ?? []).length > 0 && (
                            <>
                              <div className="muted small side-quest-label">Carrying</div>
                              <div className="pocket-items">
                                {(t.pockets.carrying ?? []).map((i, n) => (
                                  <span className="pocket-item" key={`c${n}`}>
                                    {pocketLabel(i)}
                                    <button
                                      className="pocket-x"
                                      title="Remove from the record"
                                      onClick={() => pocketRemove('carrying', n)}
                                    >
                                      ×
                                    </button>
                                  </span>
                                ))}
                              </div>
                            </>
                          )}
                          {(t.pockets.set_aside ?? []).length > 0 && (
                            <>
                              <div className="muted small side-quest-label">Set aside</div>
                              <div className="pocket-items">
                                {(t.pockets.set_aside ?? []).map((i, n) => (
                                  <span className="pocket-item pocket-item-aside" key={`s${n}`}>
                                    {pocketLabel(i)}
                                    <button
                                      className="pocket-x"
                                      title="Remove from the record"
                                      onClick={() => pocketRemove('set_aside', n)}
                                    >
                                      ×
                                    </button>
                                  </span>
                                ))}
                              </div>
                            </>
                          )}
                          <PocketAddRow onAdd={pocketAdd} />
                        </>
                      )}
                    </div>
                  )}
                  {/* The window's rule in 1:1 and group alike: time shows while
                      Realism runs for this character or the story clock runs. */}
                  {t && (!realismOff || clockRunning) && (
                    <div className="state-time">
                      {t.time.presence && (
                        <div className="stat-line"><span>{t.time.presence}</span></div>
                      )}
                      {t.time.todaySentence && (
                        <div className="stat-line">
                          <span className="muted" style={{ fontStyle: 'italic' }}>
                            {t.time.todaySentence}
                          </span>
                          <button
                            className="link-btn"
                            onClick={() =>
                              apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { abandonToday: true }))
                            }
                          >
                            Clear today
                          </button>
                        </div>
                      )}
                      {t.time.weather && (
                        <div className="stat-line">
                          <span
                            title={
                              `${t.time.weather.label} · ${t.time.weather.season}` +
                              (t.time.weather.dayLabel ? `\nToday: ${t.time.weather.dayLabel}` : '') +
                              (t.time.weather.tomorrow
                                ? `\nTomorrow: ${t.time.weather.tomorrow.emoji} ${t.time.weather.tomorrow.label}`
                                : '')
                            }
                          >
                            {t.time.weather.emoji} {t.time.weather.label}
                            {t.time.weather.tomorrow &&
                              t.time.weather.tomorrow.condition !== t.time.weather.condition && (
                                <span className="muted"> → {t.time.weather.tomorrow.emoji}</span>
                              )}
                          </span>
                          <span className="muted">{t.time.weather.season}</span>
                        </div>
                      )}
                      <div className="state-time-line">
                        <span className="state-time-when">
                          {t.time.weekday} · {t.time.timeOfDay.replace(/_/g, ' ')}
                          {t.time.clock ? ` · ${t.time.clock}` : ''}
                        </span>
                        {t.time.storyClock && (
                          <button className="link-btn story-cal-open" onClick={() => setShowCalendar(true)}>
                            📅 Story Calendar
                          </button>
                        )}
                        <span className="state-time-nudges">
                          <button
                            disabled={!clockRunning}
                            title={clockRunning ? 'Back 30 minutes' : 'Story clock is paused'}
                            onClick={() =>
                              apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: -1 }))
                            }
                          >
                            ◀ Earlier
                          </button>
                          <button
                            disabled={!clockRunning}
                            title={clockRunning ? 'Forward 30 minutes' : 'Story clock is paused'}
                            onClick={() =>
                              apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: 1 }))
                            }
                          >
                            Later ▶
                          </button>
                        </span>
                      </div>
                      <div className="time-dots">
                        {TIME_DOTS.map(([period, dot]) => (
                          <div
                            key={period}
                            className={`time-dot${t.time.timeOfDay === period ? ' active' : ''}`}
                          >
                            <span className="time-dot-mark" />
                            <span className="time-dot-label">{dot}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}
            </div>
          </details>
          {t?.groupDynamics && (
            <details className="tool-section group-dynamics" open>
              <summary><span className="card-chev" aria-hidden>❯</span>🫂 Group Dynamics{' '}
                <span className="card-sub">{t.groupDynamics.member}</span>
              </summary>
              <div className="tool-body">
                {t.groupDynamics.tracked ? (
                  <>
                    <p className="muted small">
                      How {t.groupDynamics.member} feels about the others. Read-only.
                    </p>
                    {t.groupDynamics.feelings.map((f) => (
                      <StatBar
                        key={f.id}
                        label={f.name}
                        value={`${f.tier} · ${f.score}`}
                        percent={f.percent}
                        tone={f.score < 0 ? 'danger' : ''}
                      />
                    ))}
                  </>
                ) : (
                  <p className="muted small">
                    Feelings between characters are tracked in groups of two to four characters.
                  </p>
                )}
              </div>
            </details>
          )}
          </>
        );
      case 'journal_memory':
        return t ? (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>📖 Journal &amp; Memory{' '}
              <span className="card-sub">
                {[
                  t.memory.journalEnabled ? 'recap' : '',
                  t.memory.ragEnabled ? 'RAG on' : '',
                ].filter(Boolean).join(' · ')}
              </span>
            </summary>
            <div className="tool-body">
              <ChatToolsRecap t={t} q={q} apply={apply} toggle={toggle} reloadKey={toolsKey} />
              <ChatToolsMemory
                t={t}
                focusedId={focusedId}
                reloadKey={toolsKey}
                settings={settings}
              />
              <details className="tool-section">
                <summary>Promises 🤝</summary>
                <div className="tool-body">
                  <PromisesPanel focusedId={focusedId} reloadKey={toolsKey} />
                </div>
              </details>
              <details className="tool-section">
                <summary>Belongings 🎒</summary>
                <div className="tool-body">
                  <BelongingsPanel focusedId={focusedId} reloadKey={toolsKey} />
                </div>
              </details>
            </div>
          </details>
        ) : null;
      case 'objectives':
        return t ? (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>🎯 Objectives{' '}
              <span className="card-sub">
                {[
                  focusedName,
                  `${(t.objectives.primary ? 1 : 0) + t.objectives.secondary.length} open`,
                ].filter(Boolean).join(' · ')}
              </span>
            </summary>
            <div className="tool-body">
              <ChatToolsObjectives t={t} q={q} apply={apply} />
            </div>
          </details>
        ) : null;
      case 'story_tools':
        return (
          <details className="tool-section">
            <summary><span className="card-chev" aria-hidden>❯</span>🎲 Story Tools{' '}
              <span className="card-sub">
                {[
                  t?.chaos?.enabled ? 'chaos' : '',
                  t?.time.presence ?? '',
                  'places',
                  'lore',
                ].filter(Boolean).join(' · ')}
              </span>
            </summary>
            <div className="tool-body">
              {t && <ChatToolsChaos t={t} toggle={toggle} />}
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
                      {(e.stickyLeft ?? 0) > 0 && <span className="lore-pill ok">sticky {e.stickyLeft}</span>}
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
                      <span key={n} className="lore-pill honey">
                        {n}
                      </span>
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
            </div>
          </details>
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
      <div className="insight-section" data-id="portrait">
        <div className={moodClass} style={moodStyle as React.CSSProperties | undefined} data-testid="mood-portrait" data-tone={atmosphere.tone ?? ''}>
          {isGroup ? (
            focusedId ? (
              <Portrait
                primary={`/api/chat/expression-avatar?participant=${encodeURIComponent(focusedId)}&v=${encodeURIComponent(realism.expressionLabel ?? '')}`}
                fallback={focusedPlaceholderPortrait ? undefined : focusedAvatarUrl}
                mood={realism.mood || realism.emotion}
                initial={focusedName ?? portraitName}
              />
            ) : (
              <div className="portrait-initial" aria-hidden>
                {(focusedName ?? portraitName ?? '?').charAt(0).toUpperCase()}
              </div>
            )
          ) : focusedIsHost ? (
            <LookSwiper
              characterId={characterId}
              basePrimary={`/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`}
              baseFallback={
                focusedPlaceholderPortrait ? undefined : `/api/characters/${characterId}/avatar`
              }
              mood={realism.mood || realism.emotion}
              initial={portraitName ?? focusedName}
            />
          ) : focusedAvatarUrl ? (
            <LookSwiper
              characterId={characterId}
              basePrimary={focusedAvatarUrl}
              mood={realism.mood || realism.emotion}
              initial={portraitName ?? focusedName}
            />
          ) : (
            // No picture anywhere for this participant: the window's square.
            <div className="portrait-initial" aria-hidden>
              {(portraitName ?? focusedName ?? '?').charAt(0).toUpperCase()}
            </div>
          )}
        </div>
        <button
          ref={settingsBtnRef}
          className="sidebar-main-settings"
          aria-haspopup="menu"
          aria-expanded={settingsMenu !== null}
          onClick={() => (settingsMenu ? setSettingsMenu(null) : openSettingsMenu())}
        >
          Main Settings
        </button>
        {settingsMenu && <CardMenu menu={settingsMenu} onClose={() => setSettingsMenu(null)} />}
      </div>
      <div className="sidebar-layout-pills">
        <SidebarResetPill onReset={wideReset} />
        <SidebarLockPill locked={locked} onToggle={() => setLocked(!locked)} />
      </div>
      {ordered.map((id) => (
        <div key={id} className={`wide-card${dragId === id ? ' dragging' : ''}`}>
          {card(id, section(id))}
        </div>
      ))}
      {showGroupSettings && t?.group && groupId && (
        <div className="drawer-backdrop" onClick={() => setShowGroupSettings(false)}>
          <div className="settings-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Group settings</span>
              <button className="link-btn" onClick={() => setShowGroupSettings(false)}>Close</button>
            </div>
            <GroupSettings
              group={t.group}
              groupId={groupId}
              onCommand={onCommand}
              onToggleDirector={(v) => toggle('director', v)}
              clockOn={t.time.passageEnabled}
            />
          </div>
        </div>
      )}
      {showCalendar && (
        <StoryCalendarModal
          focusedId={focusedId}
          canEdit={clockRunning}
          onClose={() => setShowCalendar(false)}
          onChanged={load}
        />
      )}
      {showChatBook && <ChatLorebookModal onClose={() => setShowChatBook(false)} />}
      {showImportBook && (
        <ImportLorebookWizard onClose={() => setShowImportBook(false)} onImported={setImportMsg} />
      )}
    </div>
  );
}
