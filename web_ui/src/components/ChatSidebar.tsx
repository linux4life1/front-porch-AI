// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop (≥1024) chat sidebar — the window's right column (PR 1a).
// The same controls the flat insight panel carries today, rearranged into
// the desktop's card tree: portrait, Main Settings, the layout pills, then
// the cast, Director, and the tool cards. Phone and tablet keep rendering
// ChatInsight (and ChatTools inside it) untouched; this tree exists only in
// the wide aside. The tools snapshot plumbing (focus scoping, embedding
// poll, mutation helpers) mirrors ChatTools.tsx so both surfaces speak to
// the same endpoints with the same payloads.

import { ReactNode, useCallback, useEffect, useRef, useState } from 'react';
import { api } from '../api/client';
import {
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
import { LookSwiper, Portrait } from './ChatAvatar';
import { CardMenu, type CardMenuItem } from './library/CardMenu';
import { ChatModelSwitcher } from '../pages/chat/ChatModelSwitcher';
import { GroupSettings } from './GroupSettings';
import { BelongingsPanel } from './BelongingsPanel';
import { PromisesPanel } from './PromisesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';
import {
  ChatToolsMemory, ChatToolsRecap, ChatToolsWiki,
} from './ChatToolsMemory';
import { ChatToolsChaos, ChatToolsNsfw, ChatToolsPockets } from './ChatToolsRealism';
import { ChatToolsAmbitions, ChatToolsObjectives } from './ChatToolsObjectives';
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
  director,
  onEditCharacter,
  onChatSettings,
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
  /** The DirectorStrip element, same move. */
  director?: ReactNode;
  /** Absent when there is no library character to edit. */
  onEditCharacter?: () => void;
  /** Opens today's Chat settings drawer (Prompt source + Generation + theme). */
  onChatSettings: () => void;
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
  const [modelSheetSignal, setModelSheetSignal] = useState(0);
  const [showGroupSettings, setShowGroupSettings] = useState(false);

  // ── Reorder (surface 'insight': the wide column IS the insight panel) ─
  const { stored, locked, commit, setLocked } = useSidebarOrder('insight');
  const visible = WIDE_DEFAULTS.filter((id) =>
    id === 'cast' ? !!castBar : id === 'director' ? !!director : true,
  );
  const ordered = resolveOrder(stored, visible, WIDE_DEFAULTS);
  const { listEl, itemEls, dragId, startDrag, dragMove, endDrag } = useReorderDrag(
    ordered,
    commit,
    !locked,
  );
  const grip = (id: string) => (
    <SidebarGrip locked={locked} onDown={(e) => startDrag(e, id)} />
  );

  const openSettingsMenu = () => {
    const r = settingsBtnRef.current?.getBoundingClientRect();
    const items: import('./library/CardMenu').CardMenuItem[] = [
      ...(onEditCharacter ? [{ label: 'Edit Character', onClick: onEditCharacter }] : []),
      { label: 'Chat Settings', onClick: onChatSettings },
      { label: 'Model Settings', onClick: () => setModelSheetSignal((n) => n + 1) },
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
        return director;
      case 'one_shot_eval':
        return <OneShotEvalControl reloadKey={toolsKey} />;
      case 'tool_calling_pill':
        return <ToolCallingPill support={toolSupport} />;
      case 'author_note':
        return (
          <details className="tool-section">
            <summary>📝 Author's Note</summary>
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
            <summary>📖 Wiki</summary>
            <div className="tool-body">
              <ChatToolsWiki t={t} q={q} apply={apply} />
            </div>
          </details>
        ) : null;
      case 'character_state':
        return (
          <details className="tool-section">
            <summary>🎭 Character State</summary>
            <div className="tool-body">
              {t && (
                <>
                  <label className="tool-toggle">
                    <span>Realism engine</span>
                    <input
                      type="checkbox"
                      aria-label="Realism engine"
                      checked={t.realismSwitch ?? t.realismEnabled}
                      disabled={t.realismAllowed === false}
                      onChange={(e) => toggle('realism', e.target.checked)}
                    />
                  </label>
                  {t.realismAllowed === false && (
                    <p className="muted small">
                      The Realism Engine is off in Porch Life, so no chat runs it. This
                      chat&apos;s own choice is kept.
                    </p>
                  )}
                </>
              )}
              {focusedIsLiteGuest ? (
                <p className="muted realism-off">
                  Lite NPC — no realism or needs tracking for this guest.
                </p>
              ) : (
                <>
                  {realism.fixation && (
                    <div className="stat-fixation">
                      <span className="fixation-label">Current fixation</span> {realism.fixation}
                    </div>
                  )}
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
                  />
                  {realism.lustOn === true && (
                    <div className="stat-line">
                      <span>Lust</span>
                      <span className="muted">
                        {realism.arousal.tier} · {realism.arousal.level}
                      </span>
                    </div>
                  )}
                  {realism.lustOn === true && realism.refractoryLabel && (
                    <div className="stat-line">
                      <span className="muted">{realism.refractoryLabel}</span>
                    </div>
                  )}
                  {t && (
                    <>
                      <ChatToolsNsfw t={t} toggle={toggle} />
                      {t.needsEnabled && (
                        <label className="tool-toggle">
                          <span>Needs</span>
                          <input
                            type="checkbox"
                            aria-label="Needs"
                            checked={t.needsEnabled}
                            disabled={t.needsAllowed === false}
                            onChange={(e) => toggle('needs', e.target.checked)}
                          />
                        </label>
                      )}
                      {t.needsEnabled && t.needsAllowed === false && (
                        <p className="muted small">
                          Off in Porch Life, so no chat runs Needs. This chat&apos;s choice is kept.
                        </p>
                      )}
                      <ChatToolsAmbitions t={t} />
                      <ChatToolsPockets
                        t={t}
                        toggle={toggle}
                        pocketRemove={pocketRemove}
                        pocketAdd={pocketAdd}
                      />
                    </>
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
              {t && (
                <>
                  <div className="stat-line">
                    <span>
                      {t.time.date ?? t.time.weekday}, day {t.time.dayCount}
                    </span>
                    <span className="muted">
                      {t.time.timeOfDay.replace(/_/g, ' ')}
                      {t.time.clock ? ` · ${t.time.clock}` : ''}
                    </span>
                  </div>
                  {t.time.presence && (
                    <div className="stat-line">
                      <span>{t.time.presence}</span>
                    </div>
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
                  {t.time.storyClock && (
                    <button className="link-btn story-cal-open" onClick={() => setShowCalendar(true)}>
                      📅 Story Calendar
                    </button>
                  )}
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
                  <div className="tool-row">
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
                  </div>
                </>
              )}
            </div>
          </details>
        );
      case 'journal_memory':
        return t ? (
          <details className="tool-section">
            <summary>📖 Journal &amp; Memory</summary>
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
        return t ? <ChatToolsObjectives t={t} q={q} apply={apply} /> : null;
      case 'story_tools':
        return (
          <details className="tool-section">
            <summary>🎲 Story Tools</summary>
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
        <button
          ref={settingsBtnRef}
          className="primary small sidebar-main-settings"
          aria-haspopup="menu"
          aria-expanded={settingsMenu !== null}
          onClick={() => (settingsMenu ? setSettingsMenu(null) : openSettingsMenu())}
        >
          Main Settings
        </button>
        {settingsMenu && <CardMenu menu={settingsMenu} onClose={() => setSettingsMenu(null)} />}
      </div>
      <div className="sidebar-layout-pills">
        <SidebarResetPill onReset={resetSidebarLayout} />
        <SidebarLockPill locked={locked} onToggle={() => setLocked(!locked)} />
      </div>
      {ordered.map((id) => (
        <div key={id} className={`wide-card${dragId === id ? ' dragging' : ''}`}>
          {card(id, section(id))}
        </div>
      ))}
      {/* Model Settings opens today's Change model sheet through the same
          component the header chip used; the chip itself is hidden on wide. */}
      <div className="model-sheet-host" aria-hidden>
        <ChatModelSwitcher openSignal={modelSheetSignal} />
      </div>
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
