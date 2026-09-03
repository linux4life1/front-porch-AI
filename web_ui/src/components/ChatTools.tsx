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
import { JournalPanel } from './JournalPanel';
import { MilestonesPanel } from './MilestonesPanel';
import { BelongingsPanel } from './BelongingsPanel';
import { PromisesPanel } from './PromisesPanel';
import { StoryCalendarModal } from './StoryCalendarModal';
import { ContextBudgetModal } from './ContextBudgetModal';
import { PocketAddRow } from './PocketAddRow';
import { ExpandableText } from './ExpandableText';
import { SummaryRecapField } from './SummaryRecapField';
import { ObjectivesPanel, type ObjectiveView } from './ObjectivesPanel';

export { TextField } from './SummaryRecapField';

interface ToolsState {
  realismEnabled: boolean;
  needsEnabled: boolean;
  realismOneShotEval: boolean;
  // Tri-state One-Shot mode (2026-08-10). Optional: absent on an older
  // facade, in which case the legacy bool still tells us on-vs-not.
  realismOneShotMode?: 'auto' | 'on' | 'off';
  memory: {
    ragEnabled: boolean;
    ragRetrievalCount: number;
    ragWindowSize: number;
    journalEnabled: boolean;
    journalInterval: number;
    journalReviewFirst?: boolean;
    importLlmertaPorchMemories?: boolean;
    growthEnabled: boolean;
    growthInterval: number;
    growthReviewFirst: boolean;
    // Host embedding-engine status (additive). Download only runs on desktop.
    embedding?: {
      available?: boolean;
      modelOnDisk?: boolean;
      settingUp?: boolean;
      setupProgress?: number;
      setupStatus?: string;
      setupError?: string | null;
      lastEngineError?: string | null;
    } | null;
    // The last reply's retrieval receipt (additive, 2026-08-10 — absent on
    // older facades; null when that reply needed no retrieval). Desktop
    // sidebar parity: what memory found / dropped / actually injected.
    lastRagReceipt?: {
      status?: 'ok' | 'error' | 'not_operational';
      found: number;
      journal_deduped: number;
      budget_trimmed: number;
      injected: Array<{
        pos: number;
        day?: number | null;
        other_chat: boolean;
        preview: string;
      }>;
    } | null;
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
  // `step` is the open quest climbing this ambition (v46); null when none.
  standingMood?: string;
  ambitions?: Array<{ text: string; progress: number; stage: string; step?: string | null }>;
  // Pockets & Wardrobe (additive, null when the switch is off). set_aside:
  // parked in the scene, still theirs — clothing entries expire at the next
  // story morning server-side, so what arrives here is always current.
  pockets?: {
    worn?: Array<{ name: string; state?: string }>;
    carrying?: Array<{ name: string; state?: string }>;
    set_aside?: Array<{ name: string; state?: string; clothing?: boolean; day?: number }>;
  } | null;
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
      // Intra-day fields (additive — absent on older facades). label/emoji
      // already lead with the current day-part; these expose the raw pieces.
      segment?: string | null;
      segmentCondition?: string | null;
      tempC?: number | null;
      tempF?: number | null;
      unit?: string | null;
      dayLabel?: string | null;
      // Deterministic forecast (additive — absent on older facades). The
      // desktop engine's walk is prefix-stable, so this is exactly what the
      // next story day will be.
      tomorrow?: {
        condition: string;
        temp: string;
        season: string;
        label: string;
        emoji: string;
      } | null;
    } | null;
    // Story Calendar (additive — absent on older facades).
    clock?: string;
    date?: string;
    dateLong?: string;
    storyClock?: string;
    storyStartDate?: string;
    presence?: string | null;
    todaySentence?: string | null;
  };
  objectives: {
    primary: ObjectiveView | null;
    secondary: ObjectiveView[];
    isChecking: boolean;
    // Additive: absent on older hosts — treat missing as on (legacy always-on).
    enabled?: boolean;
  };
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
  const [showCalendar, setShowCalendar] = useState(false);
  const [showBudget, setShowBudget] = useState(false);
  const [editingRecap, setEditingRecap] = useState(false);

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
    setEditingRecap(false);
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
  const toggle = (name: string, value: boolean) =>
    apply(api.post<ToolsState>(`/api/chat/tools/toggle${q}`, { name, value }));
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

  const obj = t.objectives.primary;
  const checking = t.objectives.isChecking;

  return (
    <div className="chat-tools">
      <Toggle label="Realism engine" value={t.realismEnabled} onChange={(v) => toggle('realism', v)} />
      <Toggle label="Needs simulation" value={t.needsEnabled} onChange={(v) => toggle('needs', v)} />
      <div className="tool-row">
        <button className="link-btn" onClick={() => setShowBudget(true)}>
          📊 Context budget — what the model was sent
        </button>
      </div>

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


      <details className="tool-section">
        <summary>Memory</summary>
        <div className="tool-body">
          <Toggle label="Use memory (RAG)" value={t.memory.ragEnabled} onChange={(v) => settings({ ragEnabled: v })} />
          {t.memory.ragEnabled && (
            <>
              {(() => {
                const e = t.memory.embedding;
                if (!e) {
                  return (
                    <p className="muted small">
                      Memory setup runs on the desktop app (one ~550&nbsp;MB local model).
                    </p>
                  );
                }
                if (e.available) {
                  return <p className="muted small">Memory engine ready — private on this computer.</p>;
                }
                if (e.settingUp) {
                  const pct =
                    typeof e.setupProgress === 'number' && e.setupProgress >= 0
                      ? Math.round(e.setupProgress * 100)
                      : null;
                  return (
                    <div className="rag-engine-status">
                      <p className="muted small">{e.setupStatus || 'Setting up memory…'}</p>
                      <div className="rag-progress-track" aria-hidden>
                        <div
                          className="rag-progress-fill"
                          style={pct == null ? { width: '30%', opacity: 0.5 } : { width: `${pct}%` }}
                        />
                      </div>
                      {pct != null && <p className="muted small">{pct}%</p>}
                    </div>
                  );
                }
                if (e.setupError || e.lastEngineError) {
                  return (
                    <p className="muted small rag-engine-error">
                      Setup failed: {e.setupError || e.lastEngineError}. Use the desktop app to
                      retry the download.
                    </p>
                  );
                }
                if (!e.modelOnDisk) {
                  return (
                    <p className="muted small">
                      Memory model not installed yet. Open this chat on the desktop app and turn
                      Memory on to download it (~550&nbsp;MB, one time).
                    </p>
                  );
                }
                return <p className="muted small">Starting memory engine…</p>;
              })()}
              <NumField
                label="Past moments per reply"
                value={t.memory.ragRetrievalCount}
                onCommit={(v) => settings({ ragRetrievalCount: v })}
              />
              <p className="muted small">How many old moments to weave into each reply (0 = all strong matches).</p>
              <NumField
                label="Messages per moment"
                value={t.memory.ragWindowSize}
                onCommit={(v) => settings({ ragWindowSize: v })}
              />
              <p className="muted small">How much of each past scene to keep (3–10 messages).</p>
              {/* What memory just did — desktop RagReceiptView parity. */}
              {(() => {
                const r = t.memory.lastRagReceipt;
                const status = r?.status ?? 'ok';
                const counts = r
                  ? [
                      r.budget_trimmed > 0 ? `${r.budget_trimmed} trimmed for space` : null,
                      r.journal_deduped > 0 ? `${r.journal_deduped} already covered by the journal` : null,
                    ].filter(Boolean)
                  : [];
                const suffix = counts.length ? ` (${counts.join(', ')})` : '';
                let summary: string;
                if (!r) {
                  summary = 'Last reply: nothing had scrolled out of view — no lookup needed.';
                } else if (status === 'error') {
                  summary =
                    'Last reply: tried to search the archive but the memory engine hit an error — nothing was brought back.';
                } else if (status === 'not_operational') {
                  summary =
                    'Last reply: older messages had scrolled out of view, but the memory engine is not ready — install/start Memory on the desktop host to look them up.';
                } else if (r.injected.length === 0) {
                  summary = `Last reply: searched the archive — nothing relevant enough to bring back.${suffix}`;
                } else {
                  summary = `Last reply: ${r.injected.length} ${r.injected.length === 1 ? 'memory' : 'memories'} woven in.${suffix}`;
                }
                return (
                  <div className="rag-receipt">
                    <p className="muted small">{summary}</p>
                    {status === 'ok' && r?.injected.map((line, i) => (
                      <div key={i} className="rag-receipt-line">
                        <strong>{line.other_chat ? 'another chat' : line.day != null ? `Day ${line.day}` : ''}</strong>{' '}
                        <ExpandableText text={line.preview} lines={4} className="muted small" />
                      </div>
                    ))}
                  </div>
                );
              })()}
            </>
          )}
          <Toggle label="Journal (memories + recap)" value={t.memory.journalEnabled} onChange={(v) => settings({ journalEnabled: v })} />
          {t.memory.journalEnabled ? (
            <>
              <NumField label="Every (msgs)" value={t.memory.journalInterval} onCommit={(v) => settings({ journalInterval: v })} />
              <Toggle
                label="Review journal before it applies"
                value={t.memory.journalReviewFirst ?? false}
                onChange={(v) => settings({ journalReviewFirst: v })}
              />
              <JournalPanel focusedId={focusedId} reloadKey={reloadKey} />
            </>
          ) : (
            <p className="muted small">
              Journal off: long-term memory AND the &quot;Where we are&quot; recap are
              paused — the character only remembers what still fits in the
              context window.
            </p>
          )}
          <Toggle
            label="Import Mafia game nights"
            value={t.memory.importLlmertaPorchMemories ?? true}
            onChange={(v) => settings({ importLlmertaPorchMemories: v })}
          />
          <p className="muted small">
            Plant LLMerta Mafia nights into The Journal when you open a matching
            chat; the character brings up the night on their next reply.
          </p>
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

      {/* What they walked in carrying, before you said anything. Reads
          "Came in …" so it can never be mistaken for a reaction to something
          the user did — which is the entire point of the feature. */}
      {!!t.standingMood && (
        <p className="muted small" style={{ margin: '0 0 10px', fontStyle: 'italic' }}>
          🌤️ Came in {t.standingMood}
        </p>
      )}
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
                {a.step?.trim() && <div className="ambition-step">↳ {a.step.trim()}</div>}
              </div>
            ))}
          </div>
        </details>
      )}

      {(() => {
        // `pockets` is null when the feature is OFF (panel absent) and an
        // EMPTY object when it is on with nothing recorded — the panel still
        // renders then, so the first item can be hand-added (desktop parity).
        if (!t.pockets) return null;
        const worn = t.pockets.worn ?? [];
        const carrying = t.pockets.carrying ?? [];
        // Parked in the scene, still theirs — greyed so "not on them" reads
        // at a glance (the desktop sidebar's Set aside group, same rules;
        // the server already filtered out clothing that expired overnight).
        const setAside = t.pockets.set_aside ?? [];
        const label = (i: { name: string; state?: string }) =>
          i.state ? `${i.name} (${i.state})` : i.name;
        return (
          <details className="tool-section" open>
            <summary>Pockets &amp; Wardrobe</summary>
            <div className="tool-body">
              <div className="muted small side-quest-label">Wearing</div>
              <div className="pocket-items">
                {worn.length === 0 ? (
                  <span className="pocket-empty">Put clothes on</span>
                ) : (
                  worn.map((i, n) => (
                    <span className="pocket-item" key={`w${n}`}>
                      {label(i)}
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
              {carrying.length > 0 && (
                <>
                  <div className="muted small side-quest-label">Carrying</div>
                  <div className="pocket-items">
                    {carrying.map((i, n) => (
                      <span className="pocket-item" key={`c${n}`}>
                        {label(i)}
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
              {setAside.length > 0 && (
                <>
                  <div className="muted small side-quest-label">Set aside</div>
                  <div className="pocket-items">
                    {setAside.map((i, n) => (
                      <span className="pocket-item pocket-item-aside" key={`s${n}`}>
                        {label(i)}
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
            </div>
          </details>
        );
      })()}

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

      <details className="tool-section">
        <summary>Chaos mode{t.chaos.enabled ? ` · ${t.chaos.pressure}%` : ''}</summary>
        <div className="tool-body">
          <Toggle label="Chaos mode" value={t.chaos.enabled} onChange={(v) => toggle('chaos', v)} />
          {t.chaos.enabled && (
            <>
              <div className="stat-line"><span>Pressure</span><span className="muted">{t.chaos.pressure}%{t.chaos.hasPendingEvent ? ' · event ready' : ''}</span></div>
              <Toggle label="Allow NSFW events" value={t.chaos.nsfwEnabled} onChange={(v) => toggle('chaosNsfw', v)} />
              <button
                disabled={t.chaos.hasPendingEvent}
                onClick={() => {
                  void api.post('/api/chat/chance-time/spin').catch(() => {});
                }}
              >
                {t.chaos.hasPendingEvent ? 'EVENT PENDING' : 'SPIN NOW'}
              </button>
            </>
          )}
        </div>
      </details>

      <ObjectivesPanel
        primary={obj}
        secondary={t.objectives.secondary}
        checking={checking}
        enabled={t.objectives.enabled !== false}
        query={q}
        apply={apply}
      />

      <details className="tool-section">
        <summary>Where we are</summary>
        <div className="tool-body">
          <SummaryRecapField
            value={t.summary.text}
            editing={editingRecap}
            onCommit={(text) => apply(api.post<ToolsState>(`/api/chat/tools/summary${q}`, { text }))}
            onStartEditing={() => setEditingRecap(true)}
            onStopEditing={() => setEditingRecap(false)}
          />
          <div className="tool-row">
            {t.summary.text.trim() !== '' && (
              <button
                type="button"
                onClick={() => setEditingRecap((v) => !v)}
              >
                {editingRecap ? 'Done' : 'Edit'}
              </button>
            )}
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
          {/* Disabled with realism off. The server's nudgeTimePeriod returns
              immediately in that state, so these used to be dead clicks: a 200
              response and a clock that never moved. Desktop hides them; the
              calendar modal below already gated on the same flag. */}
          <div className="tool-row">
            <button
              disabled={!t.realismEnabled}
              title={t.realismEnabled ? 'Back 30 minutes' : 'Realism Mode is off, so the story clock is paused'}
              onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: -1 }))}
            >◀ Earlier</button>
            <button
              disabled={!t.realismEnabled}
              title={t.realismEnabled ? 'Forward 30 minutes' : 'Realism Mode is off, so the story clock is paused'}
              onClick={() => apply(api.post<ToolsState>(`/api/chat/tools/time${q}`, { delta: 1 }))}
            >Later ▶</button>
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

      {showBudget && <ContextBudgetModal onClose={() => setShowBudget(false)} />}
    </div>
  );
}
