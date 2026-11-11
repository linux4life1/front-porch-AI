// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat "tools" sidebar — load / toggle / apply shell. Sections live in
// ChatToolsMemory / ChatToolsRealism / ChatToolsObjectives (same domains as
// the desktop facade). Section ORDER still mirrors the desktop sidebar
// (Memory → Chaos → Objectives → Summary → Scene & time → NSFW → Group).
// Rendered inside the insight panel (persistent column on desktop/landscape-
// tablet; the insight drawer on phone/portrait-tablet).

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';
import {
  SIDEBAR_DEFAULTS,
  SidebarGrip,
  resolveOrder,
  useReorderDrag,
  useSidebarOrder,
} from './sidebarReorder';
import { BelongingsPanel } from './BelongingsPanel';
import { PromisesPanel } from './PromisesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';
import { ContextBudgetModal } from './ContextBudgetModal';
import { MilestonesPanel } from './MilestonesPanel';
import { ChatToolsMemory, ChatToolsRecap, ChatToolsWiki } from './ChatToolsMemory';
import { ChatToolsChaos, ChatToolsNsfw, ChatToolsPockets } from './ChatToolsRealism';
import { ChatToolsAmbitions, ChatToolsObjectives } from './ChatToolsObjectives';
import { type ToolsState } from './ChatToolsShared';

export { TextField } from './SummaryRecapField';
export type { ToolsState } from './ChatToolsShared';

/** Scene-time periods + their single-letter dot labels (mirror the desktop
 *  realism_section _timeDotLabel exactly: D / M / LM / A / E / N). */
const TIME_DOTS: [string, string][] = [
  ['dawn', 'D'],
  ['morning', 'M'],
  ['late_morning', 'LM'],
  ['afternoon', 'A'],
  ['evening', 'E'],
  ['night', 'N'],
];

export function ChatTools({
  reloadKey,
  focusedId,
  groupId,
  cast,
}: {
  reloadKey: number;
  focusedId?: string | null;
  groupId?: string | null;
  onCommand?: (cmd: string) => void;
  /** A group chat's roster, for the story's Lead pick; absent in a 1:1. */
  cast?: { id: string; dbId: string | null; name: string }[];
}) {
  const [t, setT] = useState<ToolsState | null>(null);
  // Living Time §4: feedback line for "turn this chat into a story".
  const [storyMsg, setStoryMsg] = useState<string | null>(null);
  // Stories from group chats: who leads. '' is the first member, the
  // relay's default (docs/design/stories-from-group-chats.md §1).
  const [storyLead, setStoryLead] = useState('');
  const roster = (cast ?? []).filter((c) => c.dbId);
  const [showCalendar, setShowCalendar] = useState(false);
  const [showBudget, setShowBudget] = useState(false);

  // Scope every tools call to the focused cast participant so objectives/arousal
  // (and the snapshot returned by mutations) follow the focus.
  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';

  const load = useCallback(async () => {
    try {
      setT(await api.get<ToolsState>(`/api/chat/tools${q}`));
    } catch {
      /* no active chat / not wired — leave hidden */
    }
  }, [q]);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  // While the host is downloading the embedding model, poll tools state so the
  // progress bar moves (desktop listens to EmbeddingService; web only has GET).
  const embeddingBusy = Boolean(t?.memory?.ragEnabled && t?.memory?.embedding?.settingUp);
  useEffect(() => {
    if (!embeddingBusy) return;
    const id = window.setInterval(() => {
      void load();
    }, 1000);
    return () => window.clearInterval(id);
  }, [embeddingBusy, load]);

  // Every mutation endpoint returns the fresh (focus-scoped) tools state.
  const apply = (p: Promise<unknown>) => {
    void (p as Promise<ToolsState>).then(setT).catch(() => {});
  };
  const settings = (fields: Record<string, unknown>) =>
    apply(api.post<ToolsState>(`/api/chat/tools/settings${q}`, fields));
  const toggle = (name: string, value: boolean, extra?: Record<string, unknown>) =>
    apply(api.post<ToolsState>(`/api/chat/tools/toggle${q}`, { name, value, ...extra }));
  // The eraser: strike one wardrobe entry by hand — the same ✕ the desktop
  // chips have (a wrong entry must be one tap from corrected on every
  // surface). The endpoint answers with the fresh snapshot.
  const pocketRemove = (section: string, index: number) =>
    apply(api.post<ToolsState>(`/api/chat/tools/pocket-remove${q}`, { section, index }));
  // The other half of the eraser: hand-add an item (desktop dialog parity,
  // 2026-08-13). gift=true is handed over in-scene (they know it came from
  // you); correction=true is a wardrobe record fix (worn, no intro);
  // otherwise the Easter egg (they're surprised to find it).
  const pocketAdd = (section: string, name: string, gift: boolean, correction = false) =>
    apply(api.post<ToolsState>(`/api/chat/tools/pocket-add${q}`, { section, name, gift, correction }));

  // The remembered order: read from the host snapshot, kept live across
  // `settings_changed`, and POSTed on a drag. The host merges ids hidden
  // right now back into their stored slots.
  const { stored, locked, commit } = useSidebarOrder('tools');
  const visible = t
    ? [
        'realism_toggle',
        ...(t.realismEnabled ? ['needs_toggle'] : []),
        'context_budget',
        'wiki',
        'memory',
        'ambitions',
        'pockets',
        'our_story',
        'promises',
        'belongings',
        'chaos',
        'objectives',
        ...(t.memory.journalEnabled ? ['recap'] : []),
        'scene_time',
        'nsfw',
        ...(t.group && groupId ? ['group_settings'] : []),
      ]
    : [];
  const ordered = resolveOrder(stored, visible, SIDEBAR_DEFAULTS.tools);
  const { listEl, itemEls, dragId, startDrag, dragMove, endDrag } = useReorderDrag(
    ordered,
    commit,
    !locked,
  );

  if (!t) return null;

  const clockRunning = t.time.clockRunning ?? false;

  const grip = (id: string) => (
    <SidebarGrip locked={locked} onDown={(e) => startDrag(e, id)} />
  );
  const section = (id: string) => {
    switch (id) {
      case 'realism_toggle':
        return (
          <>
            {grip(id)}
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
              <p className="muted small">The Realism Engine is off in Porch Life, so no chat runs it. This chat&apos;s own choice is kept.</p>
            )}
          </>
        );
      case 'needs_toggle':
        return (
          <>
            {grip(id)}
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
            {t.needsAllowed === false && (
              <p className="muted small">Off in Porch Life, so no chat runs Needs. This chat&apos;s choice is kept.</p>
            )}
          </>
        );
      case 'context_budget':
        return (
          <>
            {grip(id)}
            <div className="tool-row">
              <button className="link-btn budget-link" onClick={() => setShowBudget(true)}>
                📊 Context budget — what the model was sent
              </button>
            </div>
          </>
        );
      case 'wiki':
        return (
          <>
            {grip(id)}
            <ChatToolsWiki t={t} q={q} apply={apply} />
          </>
        );
      case 'memory':
        return (
          <>
            {grip(id)}
            <ChatToolsMemory
              t={t}
              focusedId={focusedId}
              reloadKey={reloadKey}
              settings={settings}
            />
          </>
        );
      case 'ambitions':
        return (
          <>
            {grip(id)}
            <ChatToolsAmbitions t={t} />
          </>
        );
      case 'pockets':
        return (
          <>
            {grip(id)}
            <ChatToolsPockets
              t={t}
              toggle={toggle}
              pocketRemove={pocketRemove}
              pocketAdd={pocketAdd}
            />
          </>
        );
      case 'our_story':
        return (
          <>
            {grip(id)}
            <details className="tool-section">
              <summary>Our story</summary>
              <div className="tool-body">
                <MilestonesPanel focusedId={focusedId} reloadKey={reloadKey} />
                {roster.length > 0 && (
                  <div className="tool-row">
                    <label>
                      Lead{' '}
                      <select
                        data-testid="story-lead"
                        aria-label="Story lead"
                        value={storyLead}
                        onChange={(e) => setStoryLead(e.target.value)}
                      >
                        {roster.map((c, i) => (
                          <option key={c.id} value={i === 0 ? '' : c.dbId ?? ''}>{c.name}</option>
                        ))}
                        <option value="persona">You</option>
                      </select>
                    </label>
                  </div>
                )}
                <div className="tool-row">
                  <button
                    data-testid="story-from-chat"
                    onClick={async () => {
                      setStoryMsg(null);
                      try {
                        const r = await api.post<{ id: string; title: string }>(
                          '/api/chat/tools/to-story',
                          storyLead ? { lead: storyLead } : {},
                        );
                        setStoryMsg(`Created "${r.title}" — open Stories to run it.`);
                      } catch {
                        setStoryMsg('Needs a chat with a character or a group.');
                      }
                    }}
                  >
                    📖 Turn this chat into a story
                  </button>
                </div>
                {storyMsg && <p className="muted milestones-empty">{storyMsg}</p>}
              </div>
            </details>
          </>
        );
      case 'promises':
        return (
          <>
            {grip(id)}
            <details className="tool-section">
              <summary>Promises 🤝</summary>
              <div className="tool-body">
                <PromisesPanel focusedId={focusedId} reloadKey={reloadKey} />
              </div>
            </details>
          </>
        );
      case 'belongings':
        return (
          <>
            {grip(id)}
            <details className="tool-section">
              <summary>Belongings 🎒</summary>
              <div className="tool-body">
                <BelongingsPanel focusedId={focusedId} reloadKey={reloadKey} />
              </div>
            </details>
          </>
        );
      case 'chaos':
        return (
          <>
            {grip(id)}
            <ChatToolsChaos t={t} toggle={toggle} />
          </>
        );
      case 'objectives':
        return (
          <>
            {grip(id)}
            <ChatToolsObjectives t={t} q={q} apply={apply} />
          </>
        );
      case 'recap':
        return (
          <>
            {grip(id)}
            <ChatToolsRecap t={t} q={q} apply={apply} toggle={toggle} reloadKey={reloadKey} />
          </>
        );
      case 'scene_time':
        return (
          <>
            {grip(id)}
            <details className="tool-section">
              <summary>Scene &amp; time</summary>
              <div className="tool-body">
                <div className="stat-line">
                  <span>{t.time.date ?? t.time.weekday}, day {t.time.dayCount}</span>
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
                    <span className="muted" style={{ fontStyle: 'italic' }}>{t.time.todaySentence}</span>
                    <button
                      className="link-btn"
                      onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { abandonToday: true }))}
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
                        (t.time.weather.dayLabel
                          ? `\nToday: ${t.time.weather.dayLabel}`
                          : '') +
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
                    onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: -1 }))}
                  >◀ Earlier</button>
                  <button
                    disabled={!clockRunning}
                    title={clockRunning ? 'Forward 30 minutes' : 'Story clock is paused'}
                    onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: 1 }))}
                  >Later ▶</button>
                </div>
              </div>
            </details>
          </>
        );
      case 'nsfw':
        return (
          <>
            {grip(id)}
            <ChatToolsNsfw t={t} toggle={toggle} />
          </>
        );
      case 'group_settings':
        return t.group && groupId ? (
          <>
            {grip(id)}
            <details className="tool-section" open>
              <summary>Edit group…</summary>
              <div className="tool-body">
                <a className="primary" href={`#/groups/${groupId}/edit`}>
                  Edit group…
                </a>
              </div>
            </details>
          </>
        ) : null;
    }
    return null;
  };

  return (
    <div
      className="chat-tools"
      ref={listEl}
      onPointerMove={dragMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
      onLostPointerCapture={endDrag}
    >
      {ordered.map((id) => (
        <div
          key={id}
          className={`tools-section${dragId === id ? ' dragging' : ''}`}
          data-id={id}
          ref={(el) => {
            if (el) itemEls.current.set(id, el);
            else itemEls.current.delete(id);
          }}
        >
          {section(id)}
        </div>
      ))}
      {showCalendar && (
        <StoryCalendarModal
          focusedId={focusedId}
          canEdit={clockRunning}
          onClose={() => setShowCalendar(false)}
          onChanged={load}
        />
      )}
      {showBudget && <ContextBudgetModal onClose={() => setShowBudget(false)} />}
    </div>
  );
}
