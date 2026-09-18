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
import { GroupSettings } from './GroupSettings';
import { BelongingsPanel } from './BelongingsPanel';
import { PromisesPanel } from './PromisesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';
import { ContextBudgetModal } from './ContextBudgetModal';
import { MilestonesPanel } from './MilestonesPanel';
import { ChatToolsMemory, ChatToolsRecap, ChatToolsWiki } from './ChatToolsMemory';
import { ChatToolsChaos, ChatToolsNsfw, ChatToolsPockets } from './ChatToolsRealism';
import { ChatToolsAmbitions, ChatToolsObjectives, ChatToolsStandingMood } from './ChatToolsObjectives';
import { Toggle, type ToolsState } from './ChatToolsShared';

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
  onCommand,
}: {
  reloadKey: number;
  focusedId?: string | null;
  groupId?: string | null;
  onCommand?: (cmd: string) => void;
}) {
  const [t, setT] = useState<ToolsState | null>(null);
  // Living Time §4: feedback line for "turn this chat into a story".
  const [storyMsg, setStoryMsg] = useState<string | null>(null);
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
  // Same endpoint, string value — the one tri-state control (see the route's
  // oneShotMode case). Falls back to the legacy bool on an older facade.
  const oneShotMode = t?.realismOneShotMode ?? (t?.realismOneShotEval ? 'on' : 'auto');
  const setOneShotMode = (value: 'auto' | 'on' | 'off') =>
    apply(api.post<ToolsState>(`/api/chat/tools/toggle${q}`, { name: 'oneShotMode', value }));

  if (!t) return null;

  const clockRunning = t.time.clockRunning ?? t.realismEnabled;

  return (
    <div className="chat-tools">
      <Toggle label="Realism engine" value={t.realismEnabled} onChange={(v) => toggle('realism', v)} />
      <Toggle label="Needs simulation" value={t.needsEnabled} onChange={(v) => toggle('needs', v)} />
      <div className="tool-row">
        <button className="link-btn" onClick={() => setShowBudget(true)}>
          📊 Context budget — what the model was sent
        </button>
      </div>
      <ChatToolsWiki t={t} q={q} apply={apply} />

      <details className="tool-section">
        <summary>Realism performance</summary>
        <div className="tool-body">
          <div className="tool-toggle">
            <span>One-Shot Eval</span>
            <span className="mode-seg" role="radiogroup" aria-label="One-Shot Eval mode">
              {(['auto', 'on', 'off'] as const).map((m) => (
                <button
                  key={m}
                  role="radio"
                  aria-checked={oneShotMode === m}
                  className={`mode-seg-btn${oneShotMode === m ? ' selected' : ''}`}
                  onClick={() => setOneShotMode(m)}
                >
                  {m === 'auto' ? 'Auto' : m === 'on' ? 'On' : 'Off'}
                </button>
              ))}
            </span>
          </div>
          <p className="muted small">
            Fuses the realism evals into a single LLM call for roughly double the processing speed.
            Auto uses it on remote AI services that support tool calls, and keeps the safer
            multi-call path on local models, where small models can struggle with the combined
            prompt.
          </p>
        </div>
      </details>

      <ChatToolsMemory
        t={t}
        focusedId={focusedId}
        reloadKey={reloadKey}
        settings={settings}
      />

      <ChatToolsStandingMood t={t} />
      <ChatToolsAmbitions t={t} />

      <ChatToolsPockets t={t} pocketRemove={pocketRemove} pocketAdd={pocketAdd} />

      <details className="tool-section">
        <summary>Our story</summary>
        <div className="tool-body">
          <MilestonesPanel focusedId={focusedId} reloadKey={reloadKey} />
          <div className="tool-row">
            <button
              onClick={async () => {
                setStoryMsg(null);
                try {
                  const r = await api.post<{ id: string; title: string }>(
                    '/api/chat/tools/to-story',
                    {},
                  );
                  setStoryMsg(`Created "${r.title}" — open Stories to run it.`);
                } catch {
                  setStoryMsg('Needs a 1:1 chat with a character.');
                }
              }}
            >
              📖 Turn this chat into a story
            </button>
          </div>
          {storyMsg && <p className="muted milestones-empty">{storyMsg}</p>}
        </div>
      </details>

      <details className="tool-section">
        <summary>Promises 🤝</summary>
        <div className="tool-body">
          <PromisesPanel focusedId={focusedId} reloadKey={reloadKey} />
        </div>
      </details>

      <details className="tool-section">
        <summary>Belongings 🎒</summary>
        <div className="tool-body">
          <BelongingsPanel focusedId={focusedId} reloadKey={reloadKey} />
        </div>
      </details>

      <ChatToolsChaos t={t} toggle={toggle} />

      <ChatToolsObjectives t={t} q={q} apply={apply} />

      <ChatToolsRecap t={t} q={q} apply={apply} toggle={toggle} reloadKey={reloadKey} />

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
          {/* Disabled when the clock is not actually moving (engine off AND
              standalone off, or passage off). Desktop TimeStrip uses the
              same StoryClock.isRunning gate. */}
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
          <Toggle label="Auto passage of time" value={t.time.passageEnabled} onChange={(v) => toggle('passageOfTime', v)} />
        </div>
      </details>

      <ChatToolsNsfw t={t} toggle={toggle} />

      {t.group && groupId && (
        <GroupSettings
          group={t.group}
          groupId={groupId}
          onCommand={onCommand}
          onToggleDirector={(v) => toggle('director', v)}
        />
      )}

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
