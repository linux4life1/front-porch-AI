// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat "tools" sidebar — the memory / chaos / objectives / summary /
// scene-time / NSFW sections the desktop shows beside a chat. Reads
// /api/chat/tools and drives the same ChatService/StorageService mutations the
// desktop sidebar does (no logic lives here). Section ORDER mirrors the desktop
// sidebar (Memory → Chaos → Objectives → Summary → Scene & time → NSFW → Group).
// Rendered inside the insight panel (persistent column on desktop/landscape-
// tablet; the insight drawer on phone/portrait-tablet).

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';
import { GroupSettings, type GroupBlock } from './GroupSettings';
import { GrowthPanel } from './GrowthPanel';
import { MilestonesPanel } from './MilestonesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';

interface ObjectiveTask {
  description: string;
  completed: boolean;
}
interface ObjectiveView {
  id: string;
  objective: string;
  isPrimary: boolean;
  checkFrequency: number;
  tasks: ObjectiveTask[];
}
interface ToolsState {
  realismEnabled: boolean;
  needsEnabled: boolean;
  realismOneShotEval: boolean;
  memory: {
    ragEnabled: boolean;
    ragRetrievalCount: number;
    ragWindowSize: number;
    journalEnabled: boolean;
    journalInterval: number;
    growthEnabled: boolean;
    growthInterval: number;
    growthReviewFirst: boolean;
  };
  // The Journal's per-chat recap ("Where we are") — key kept as `summary`
  // to match the facade block name.
  summary: {
    text: string;
    paused: boolean;
    isGenerating: boolean;
    lastIndex: number;
  };
  chaos: { enabled: boolean; nsfwEnabled: boolean; pressure: number; hasPendingEvent: boolean };
  nsfw: { cooldownEnabled: boolean; cooldownTurnsRemaining: number; arousalLevel: number; arousalTier: string };
  // Ambitions (Living Time §6, additive — absent on older facades).
  ambitions?: Array<{ text: string; progress: number; stage: string }>;
  time: {
    timeOfDay: string;
    dayCount: number;
    weekday: string;
    passageEnabled: boolean;
    // Living Time story weather (additive — absent on older facades, null
    // when the feature is off).
    weather?: {
      condition: string;
      temp: string;
      season: string;
      label: string;
      emoji: string;
    } | null;
    // Story Calendar (additive — absent on older facades).
    clock?: string;
    date?: string;
    dateLong?: string;
    storyClock?: string;
    storyStartDate?: string;
  };
  objectives: { primary: ObjectiveView | null; secondary: ObjectiveView[]; isChecking: boolean };
  focusedId?: string | null;
  group?: GroupBlock | null;
}

/** Small labelled on/off switch. */
function Toggle({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <label className="tool-toggle">
      <span>{label}</span>
      <input type="checkbox" checked={value} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

/** Number field that commits on blur / Enter (avoids a save per keystroke). */
function NumField({
  label,
  value,
  onCommit,
}: {
  label: string;
  value: number;
  onCommit: (v: number) => void;
}) {
  const [draft, setDraft] = useState(String(value));
  useEffect(() => setDraft(String(value)), [value]);
  const commit = () => {
    const n = parseInt(draft, 10);
    if (!Number.isNaN(n) && n !== value) onCommit(n);
  };
  return (
    <label className="tool-num">
      <span>{label}</span>
      <input
        type="number"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => e.key === 'Enter' && commit()}
      />
    </label>
  );
}

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
  const [goal, setGoal] = useState('');
  const [showCalendar, setShowCalendar] = useState(false);

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

  // Every mutation endpoint returns the fresh (focus-scoped) tools state.
  const apply = (p: Promise<ToolsState>) => {
    void p.then(setT).catch(() => {});
  };
  const settings = (fields: Record<string, unknown>) =>
    apply(api.post<ToolsState>(`/api/chat/tools/settings${q}`, fields));
  const toggle = (name: string, value: boolean) =>
    apply(api.post<ToolsState>(`/api/chat/tools/toggle${q}`, { name, value }));

  if (!t) return null;

  const obj = t.objectives.primary;
  const checking = t.objectives.isChecking;

  return (
    <div className="chat-tools">
      <Toggle label="Realism engine" value={t.realismEnabled} onChange={(v) => toggle('realism', v)} />
      <Toggle label="Needs simulation" value={t.needsEnabled} onChange={(v) => toggle('needs', v)} />

      <details className="tool-section">
        <summary>Realism performance</summary>
        <div className="tool-body">
          <Toggle
            label="One-Shot Eval (Experimental)"
            value={t.realismOneShotEval}
            onChange={(v) => toggle('oneShotEval', v)}
          />
          <p className="muted small">
            Fuses relationship + scene evals into a single LLM call to double the processing speed.
            May be less accurate on &lt; 8B param models.
          </p>
        </div>
      </details>


      <details className="tool-section">
        <summary>Memory</summary>
        <div className="tool-body">
          <Toggle label="Use memory (RAG)" value={t.memory.ragEnabled} onChange={(v) => settings({ ragEnabled: v })} />
          {t.memory.ragEnabled && (
            <>
              <NumField label="Retrieve count" value={t.memory.ragRetrievalCount} onCommit={(v) => settings({ ragRetrievalCount: v })} />
              <NumField label="Window size" value={t.memory.ragWindowSize} onCommit={(v) => settings({ ragWindowSize: v })} />
            </>
          )}
          <Toggle label="Journal (memories + recap)" value={t.memory.journalEnabled} onChange={(v) => settings({ journalEnabled: v })} />
          {t.memory.journalEnabled ? (
            <NumField label="Every (msgs)" value={t.memory.journalInterval} onCommit={(v) => settings({ journalInterval: v })} />
          ) : (
            <p className="muted small">
              Journal off: long-term memory AND the &quot;Where we are&quot; recap are
              paused — the character only remembers what still fits in the
              context window.
            </p>
          )}
        </div>
      </details>

      <details className="tool-section">
        <summary>Growth 🌱</summary>
        <div className="tool-body">
          <Toggle label="Character growth" value={t.memory.growthEnabled} onChange={(v) => settings({ growthEnabled: v })} />
          {!t.memory.growthEnabled && (
            <p className="muted small">
              Characters grow small, evidence-backed &quot;rings&quot; as you chat — the
              original card is always preserved.
            </p>
          )}
          {t.memory.growthEnabled && (
            <>
              <NumField label="Check every (msgs)" value={t.memory.growthInterval} onCommit={(v) => settings({ growthInterval: v })} />
              <Toggle
                label="Review growth before it applies"
                value={t.memory.growthReviewFirst}
                onChange={(v) => settings({ growthReviewFirst: v })}
              />
              <GrowthPanel focusedId={focusedId} reloadKey={reloadKey} />
            </>
          )}
        </div>
      </details>

      {(t.ambitions?.length ?? 0) > 0 && (
        <details className="tool-section" open>
          <summary>Ambitions</summary>
          <div className="tool-body">
            {t.ambitions!.map((a, i) => (
              <div key={i} className="ambition-row" title={`${a.text} — ${a.stage}`}>
                <div className="ambition-line">
                  <span>🧭 {a.text}</span>
                  <em className="ambition-stage">{a.stage}</em>
                </div>
                <div className="ambition-bar">
                  <div
                    className="ambition-bar-fill"
                    style={{ width: `${Math.min(100, Math.max(0, a.progress))}%` }}
                  />
                </div>
              </div>
            ))}
          </div>
        </details>
      )}

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
        <summary>Chaos mode{t.chaos.enabled ? ` · ${t.chaos.pressure}%` : ''}</summary>
        <div className="tool-body">
          <Toggle label="Chaos mode" value={t.chaos.enabled} onChange={(v) => toggle('chaos', v)} />
          {t.chaos.enabled && (
            <>
              <div className="stat-line"><span>Pressure</span><span className="muted">{t.chaos.pressure}%{t.chaos.hasPendingEvent ? ' · event ready' : ''}</span></div>
              <Toggle label="Allow NSFW events" value={t.chaos.nsfwEnabled} onChange={(v) => toggle('chaosNsfw', v)} />
            </>
          )}
        </div>
      </details>

      <details className="tool-section" open={checking}>
        <summary>
          Objectives{obj || t.objectives.secondary.length > 0 ? '' : ' (none)'}
          {checking && <span className="obj-checking-tag"> · checking…</span>}
        </summary>
        <div className="tool-body">
          {checking && (
            <div className="obj-checking"><span className="proc-spinner sm" aria-hidden /> Checking objective &amp; task completion…</div>
          )}
          {obj ? (
            <>
              <div className="stat-line"><strong>{obj.objective}</strong></div>
              {obj.tasks.length > 0 && (
                <ul className="task-list">
                  {obj.tasks.map((task, i) => (
                    <li key={i}>
                      <label className="task-item">
                        <input
                          type="checkbox"
                          checked={task.completed}
                          onChange={() => apply(api.post<ToolsState>(`/api/chat/tools/task${q}`, { action: 'toggle', id: obj.id, taskIndex: i }))}
                        />
                        <span className={task.completed ? 'done' : ''}>{task.description}</span>
                        <button className="icon-btn" title="Remove" onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/task${q}`, { action: 'remove', id: obj.id, taskIndex: i }))}>🗑</button>
                      </label>
                    </li>
                  ))}
                </ul>
              )}
              <div className="tool-row">
                <button disabled={checking} onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'generate', id: obj.id }))}>
                  Generate tasks
                </button>
                <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'clear', id: obj.id }))}>Clear</button>
              </div>
            </>
          ) : (
            <div className="tool-row">
              <input
                placeholder="Set a goal for this character…"
                value={goal}
                onChange={(e) => setGoal(e.target.value)}
              />
              <button
                className="primary"
                disabled={!goal.trim()}
                onClick={() => {
                  apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'set', goal }));
                  setGoal('');
                }}
              >
                Set
              </button>
            </div>
          )}
          {t.objectives.secondary.length > 0 && (
            <>
              <div className="muted small side-quest-label">Side quests</div>
              {t.objectives.secondary.map((sq) => {
                const doneCount = sq.tasks.filter((x) => x.completed).length;
                return (
                  <div className="side-quest" key={sq.id}>
                    <div className="stat-line">
                      <strong>{sq.objective}</strong>
                      {sq.tasks.length > 0 && <span className="muted">{doneCount}/{sq.tasks.length}</span>}
                    </div>
                    {sq.tasks.length > 0 && (
                      <ul className="task-list">
                        {sq.tasks.map((task, i) => (
                          <li key={i}>
                            <label className="task-item">
                              <input
                                type="checkbox"
                                checked={task.completed}
                                onChange={() => apply(api.post<ToolsState>(`/api/chat/tools/task${q}`, { action: 'toggle', id: sq.id, taskIndex: i }))}
                              />
                              <span className={task.completed ? 'done' : ''}>{task.description}</span>
                              <button className="icon-btn" title="Remove" onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/task${q}`, { action: 'remove', id: sq.id, taskIndex: i }))}>🗑</button>
                            </label>
                          </li>
                        ))}
                      </ul>
                    )}
                    <div className="tool-row">
                      <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'promote', id: sq.id }))}>
                        Make primary
                      </button>
                      <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'clear', id: sq.id }))}>Clear</button>
                    </div>
                  </div>
                );
              })}
            </>
          )}
        </div>
      </details>

      <details className="tool-section">
        <summary>Where we are</summary>
        <div className="tool-body">
          <textarea
            className="note-input"
            rows={4}
            value={t.summary.text}
            onChange={(e) => setT({ ...t, summary: { ...t.summary, text: e.target.value } })}
            onBlur={() => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { text: t.summary.text }))}
            placeholder="The character's recap of where things stand…"
          />
          <div className="tool-row">
            <button
              className="primary"
              disabled={t.summary.isGenerating}
              onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { action: 'regenerate' }))}
            >
              {t.summary.isGenerating ? 'Generating…' : 'Regenerate'}
            </button>
          </div>
          <Toggle label="Pause journal updates" value={t.summary.paused} onChange={(v) => toggle('summaryPaused', v)} />
        </div>
      </details>

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
          {t.time.weather && (
            <div className="stat-line">
              <span title={`${t.time.weather.label} · ${t.time.weather.season}`}>
                {t.time.weather.emoji} {t.time.weather.label}
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
            <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: -1 }))}>◀ Earlier</button>
            <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: 1 }))}>Later ▶</button>
          </div>
          <Toggle label="Auto passage of time" value={t.time.passageEnabled} onChange={(v) => toggle('passageOfTime', v)} />
        </div>
      </details>

      <details className="tool-section">
        <summary>NSFW</summary>
        <div className="tool-body">
          <div className="stat-line"><span>Arousal</span><span className="muted">{t.nsfw.arousalTier} · {t.nsfw.arousalLevel}</span></div>
          <Toggle label={t.group ? 'NSFW Enhancements (all members)' : 'NSFW Enhancements'} value={t.nsfw.cooldownEnabled} onChange={(v) => toggle('nsfwCooldown', v)} />
          {t.nsfw.cooldownEnabled && t.nsfw.cooldownTurnsRemaining > 0 && (
            <div className="stat-line"><span>Cooldown</span><span className="muted">{t.nsfw.cooldownTurnsRemaining} turns</span></div>
          )}
        </div>
      </details>

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
          canEdit={t.realismEnabled}
          onClose={() => setShowCalendar(false)}
          onChanged={load}
        />
      )}
    </div>
  );
}
