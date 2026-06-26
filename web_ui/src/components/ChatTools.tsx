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

export function ChatTools({ reloadKey }: { reloadKey: number }) {
  const [t, setT] = useState<ToolsState | null>(null);
  const [goal, setGoal] = useState('');

  const load = useCallback(async () => {
    try {
      setT(await api.get<ToolsState>('/api/chat/tools'));
    } catch {
      /* no active chat / not wired — leave hidden */
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load, reloadKey]);

  // Every mutation endpoint returns the fresh tools state, so we just swap it in.
  const apply = (p: Promise<ToolsState>) => {
    void p.then(setT).catch(() => {});
  };
  const settings = (fields: Record<string, unknown>) =>
    apply(api.post<ToolsState>('/api/chat/tools/settings', fields));
  const toggle = (name: string, value: boolean) =>
    apply(api.post<ToolsState>('/api/chat/tools/toggle', { name, value }));

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
            <button onClick={() => apply(api.post<ToolsState>('/api/chat/tools/time', { delta: -1 }))}>◀ Earlier</button>
            <button onClick={() => apply(api.post<ToolsState>('/api/chat/tools/time', { delta: 1 }))}>Later ▶</button>
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
            onBlur={() => apply(api.post<ToolsState>('/api/chat/tools/summary', { text: t.summary.text }))}
            placeholder="Running summary of the conversation…"
          />
          <div className="tool-row">
            <button
              className="primary"
              disabled={t.summary.isGenerating}
              onClick={() => apply(api.post<ToolsState>('/api/chat/tools/summary', { action: 'regenerate' }))}
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
                          onChange={() => apply(api.post<ToolsState>('/api/chat/tools/task', { action: 'toggle', id: obj.id, taskIndex: i }))}
                        />
                        <span className={task.completed ? 'done' : ''}>{task.description}</span>
                        <button className="icon-btn" title="Remove" onClick={() => apply(api.post<ToolsState>('/api/chat/tools/task', { action: 'remove', id: obj.id, taskIndex: i }))}>🗑</button>
                      </label>
                    </li>
                  ))}
                </ul>
              )}
              <div className="tool-row">
                <button disabled={t.objectives.isChecking} onClick={() => apply(api.post<ToolsState>('/api/chat/tools/objective', { action: 'generate', id: obj.id }))}>
                  Generate tasks
                </button>
                <button onClick={() => apply(api.post<ToolsState>('/api/chat/tools/objective', { action: 'clear', id: obj.id }))}>Clear</button>
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
                  apply(api.post<ToolsState>('/api/chat/tools/objective', { action: 'set', goal }));
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
    </div>
  );
}
