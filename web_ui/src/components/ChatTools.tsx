// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat "tools" sidebar — the memory / summary / chaos / NSFW / scene-time /
// objective sections the desktop shows beside a chat. Reads /api/chat/tools and
// drives the same ChatService/StorageService mutations the desktop sidebar does
// (no logic lives here). Rendered inside the insight panel (persistent column on
// desktop/landscape-tablet; the insight drawer on phone/portrait-tablet).

import { useCallback, useEffect, useState } from 'react';
import { api } from '../api/client';

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
  memory: {
    ragEnabled: boolean;
    ragRetrievalCount: number;
    ragWindowSize: number;
    autoPersonaEnabled: boolean;
    autoPersonaInterval: number;
    evolutionEnabled: boolean;
    evolutionInterval: number;
    evolutionCount: number;
  };
  summary: {
    text: string;
    paused: boolean;
    isGenerating: boolean;
    lastIndex: number;
    interval: number;
    maxWords: number;
    prompt: string;
  };
  chaos: { enabled: boolean; nsfwEnabled: boolean; pressure: number; hasPendingEvent: boolean };
  nsfw: { cooldownEnabled: boolean; cooldownTurnsRemaining: number; arousalLevel: number; arousalTier: string };
  time: { timeOfDay: string; dayCount: number; weekday: string; passageEnabled: boolean };
  objectives: { primary: ObjectiveView | null; secondary: ObjectiveView[]; isChecking: boolean };
  focusedId?: string | null;
  group?: GroupBlock | null;
}
interface GroupBlock {
  name: string;
  turnOrder: string;
  directorMode: boolean;
  systemPrompt: string;
  scenario: string;
  firstMessage: string;
  members: { id: string; name: string; prompt: string }[];
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
  const [goal, setGoal] = useState('');

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

  return (
    <div className="chat-tools">
      <Toggle label="Realism engine" value={t.realismEnabled} onChange={(v) => toggle('realism', v)} />

      <details className="tool-section" open>
        <summary>Scene &amp; time</summary>
        <div className="tool-body">
          <div className="stat-line">
            <span>{t.time.weekday}, day {t.time.dayCount}</span>
            <span className="muted">{t.time.timeOfDay.replace(/_/g, ' ')}</span>
          </div>
          <div className="tool-row">
            <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: -1 }))}>◀ Earlier</button>
            <button onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: 1 }))}>Later ▶</button>
          </div>
          <Toggle label="Auto passage of time" value={t.time.passageEnabled} onChange={(v) => toggle('passageOfTime', v)} />
        </div>
      </details>

      <details className="tool-section">
        <summary>Summary</summary>
        <div className="tool-body">
          <textarea
            className="note-input"
            rows={4}
            value={t.summary.text}
            onChange={(e) => setT({ ...t, summary: { ...t.summary, text: e.target.value } })}
            onBlur={() => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { text: t.summary.text }))}
            placeholder="Running summary of the conversation…"
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
          <Toggle label="Pause auto-summary" value={t.summary.paused} onChange={(v) => toggle('summaryPaused', v)} />
          <NumField label="Update every (msgs)" value={t.summary.interval} onCommit={(v) => settings({ summaryInterval: v })} />
          <NumField label="Max words" value={t.summary.maxWords} onCommit={(v) => settings({ summaryMaxWords: v })} />
        </div>
      </details>

      <details className="tool-section">
        <summary>Objectives{obj ? '' : ' (none)'}</summary>
        <div className="tool-body">
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
                <button disabled={t.objectives.isChecking} onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/objective${q}`, { action: 'generate', id: obj.id }))}>
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

      <details className="tool-section">
        <summary>NSFW</summary>
        <div className="tool-body">
          <div className="stat-line"><span>Arousal</span><span className="muted">{t.nsfw.arousalTier} · {t.nsfw.arousalLevel}</span></div>
          <Toggle label="Post-climax cooldown" value={t.nsfw.cooldownEnabled} onChange={(v) => toggle('nsfwCooldown', v)} />
          {t.nsfw.cooldownEnabled && t.nsfw.cooldownTurnsRemaining > 0 && (
            <div className="stat-line"><span>Cooldown</span><span className="muted">{t.nsfw.cooldownTurnsRemaining} turns</span></div>
          )}
        </div>
      </details>

      <details className="tool-section">
        <summary>Memory &amp; evolution</summary>
        <div className="tool-body">
          <Toggle label="Use memory (RAG)" value={t.memory.ragEnabled} onChange={(v) => settings({ ragEnabled: v })} />
          {t.memory.ragEnabled && (
            <>
              <NumField label="Retrieve count" value={t.memory.ragRetrievalCount} onCommit={(v) => settings({ ragRetrievalCount: v })} />
              <NumField label="Window size" value={t.memory.ragWindowSize} onCommit={(v) => settings({ ragWindowSize: v })} />
            </>
          )}
          <Toggle label="Auto-persona learning" value={t.memory.autoPersonaEnabled} onChange={(v) => settings({ autoPersonaEnabled: v })} />
          {t.memory.autoPersonaEnabled && (
            <NumField label="Every (msgs)" value={t.memory.autoPersonaInterval} onCommit={(v) => settings({ autoPersonaInterval: v })} />
          )}
          <Toggle label="Character evolution" value={t.memory.evolutionEnabled} onChange={(v) => settings({ evolutionEnabled: v })} />
          {t.memory.evolutionEnabled && (
            <>
              <NumField label="Every (msgs)" value={t.memory.evolutionInterval} onCommit={(v) => settings({ evolutionInterval: v })} />
              <div className="stat-line"><span>Evolutions</span><span className="muted">{t.memory.evolutionCount}</span></div>
            </>
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
    </div>
  );
}

/** Group-only settings — gated on the presence of the group block (i.e. a group
 *  chat). Turn order is applied live via the /turnorder command; the rest save
 *  to the group's settings (name / prompts / scenario / per-member overrides). */
function GroupSettings({
  group,
  groupId,
  onCommand,
  onToggleDirector,
}: {
  group: GroupBlock;
  groupId: string;
  onCommand?: (cmd: string) => void;
  onToggleDirector: (v: boolean) => void;
}) {
  const [systemPrompt, setSystemPrompt] = useState(group.systemPrompt);
  const [scenario, setScenario] = useState(group.scenario);
  const [firstMessage, setFirstMessage] = useState(group.firstMessage);
  const [prompts, setPrompts] = useState<Record<string, string>>(
    Object.fromEntries(group.members.map((m) => [m.id, m.prompt])),
  );
  useEffect(() => {
    setSystemPrompt(group.systemPrompt);
    setScenario(group.scenario);
    setFirstMessage(group.firstMessage);
    setPrompts(Object.fromEntries(group.members.map((m) => [m.id, m.prompt])));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [groupId]);

  const save = (fields: Record<string, unknown>) =>
    void api.post(`/api/groups/${groupId}/settings`, fields).catch(() => {});

  return (
    <details className="tool-section">
      <summary>Group settings</summary>
      <div className="tool-body">
        <div className="tool-row">
          <span className="muted small">Turn order:</span>
          <button
            className={group.turnOrder === 'roundRobin' ? 'primary small' : 'small'}
            onClick={() => onCommand?.('/turnorder roundrobin')}
          >
            Round-robin
          </button>
          <button
            className={group.turnOrder === 'random' ? 'primary small' : 'small'}
            onClick={() => onCommand?.('/turnorder random')}
          >
            Random
          </button>
        </div>
        <Toggle label="Director mode" value={group.directorMode} onChange={onToggleDirector} />
        <label>
          Group system prompt
          <textarea rows={3} value={systemPrompt} onChange={(e) => setSystemPrompt(e.target.value)} onBlur={() => save({ systemPrompt })} />
        </label>
        <label>
          Group scenario
          <textarea rows={2} value={scenario} onChange={(e) => setScenario(e.target.value)} onBlur={() => save({ scenario })} />
        </label>
        <label>
          Group first message
          <textarea rows={2} value={firstMessage} onChange={(e) => setFirstMessage(e.target.value)} onBlur={() => save({ firstMessage })} />
        </label>
        <h4 className="section-label">Per-member prompt overrides</h4>
        {group.members.map((m) => (
          <label key={m.id}>
            {m.name}
            <textarea
              rows={2}
              value={prompts[m.id] ?? ''}
              onChange={(e) => setPrompts({ ...prompts, [m.id]: e.target.value })}
              onBlur={() => save({ characterSystemPrompts: prompts })}
              placeholder="Extra instructions just for this member…"
            />
          </label>
        ))}
      </div>
    </details>
  );
}
