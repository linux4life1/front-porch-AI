// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import { ChatTools } from '../components/ChatTools';

interface Chips {
  bondDelta?: number;
  trustDelta?: number;
  arousalDelta?: number;
  emotionLabel?: string;
  bondReason?: string;
  trustReason?: string;
  timeSkipTo?: string;
  chanceTimeEvent?: string;
  needsDeltas?: Record<string, number>;
}
interface Message {
  index: number;
  sender: string;
  text: string;
  isUser: boolean;
  chips?: Chips;
  swipeCount?: number;
  swipeIndex?: number;
  hasThinking?: boolean;
  thinkingContent?: string;
}
interface Realism {
  bond: { score: number; tier: string; percent: number };
  longTerm: { score: number; tier: string; percent: number };
  trust: { level: number; tier: string; percent: number };
  emotion: string;
  emotionIntensity: string;
  mood: string;
  arousal: { level: number; tier: string };
  fixation: string;
  needsEnabled: boolean;
  needs: Record<string, number>;
}
interface LoreEntry {
  key: string;
  name: string;
  isTriggered: boolean;
  constant: boolean;
}
interface ChatState {
  character: { name: string; id: string } | null;
  sessionId: string | null;
  messages: Message[];
  isGenerating: boolean;
  isGroupMode?: boolean;
  realism?: Realism;
  lorebook?: LoreEntry[];
  authorNote?: string;
  authorNoteDepth?: number;
  greetingIndex?: number;
  totalGreetings?: number;
  expressionLabel?: string;
}
interface SessionSummary {
  id: string;
  preview: string;
  message_count: number;
  user_message_count: number;
  date: string;
  session_name?: string;
}

// Mirrors ChatCommandHandler.commands (lib/services/chat/chat_command_handler.dart)
// — the single source of truth for the desktop "type /" helper. Keep in sync if
// commands change. Display-only cheat sheet (clicking inserts the command); no
// autocomplete/filtering. All are dispatched server-side in ChatService.
const SLASH_COMMANDS: { cmd: string; args: string; desc: string }[] = [
  { cmd: '/create', args: '<name>: <concept>', desc: 'Create a new guest NPC and bring them into the scene' },
  { cmd: '/join', args: '[--full] [name]', desc: 'Bring a character in — --full makes a full member; in a group, always full' },
  { cmd: '/promote', args: '', desc: 'Turn the present scene into a full group (everyone becomes a full member)' },
  { cmd: '/speak', args: '[name]', desc: 'Make someone present take a turn now — a guest, or a group member by name' },
  { cmd: '/exit', args: '[name]', desc: 'A guest leaves (narrated); in a group, removes that full member by name' },
  { cmd: '/turnorder', args: '[random | <name>, …]', desc: 'Set how a group takes turns: round-robin, random, or an explicit order' },
  { cmd: '/scan', args: '', desc: 'Scan the scene for a new recurring character to add' },
  { cmd: '/expression', args: '[emotion]', desc: "Set the character's expression; omit the emotion to clear it" },
];

export function ChatPage() {
  const navigate = useNavigate();
  const [state, setState] = useState<ChatState | null>(null);
  const [draft, setDraft] = useState('');
  const [streaming, setStreaming] = useState('');
  const [showSessions, setShowSessions] = useState(false);
  const [showStats, setShowStats] = useState(false);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(false);
  const [editIndex, setEditIndex] = useState<number | null>(null);
  const [editDraft, setEditDraft] = useState('');
  // Bumps whenever chat state refreshes (incl. WS chat_updated) so the tools
  // sidebar refetches its own snapshot in lock-step.
  const [toolsBump, setToolsBump] = useState(0);
  // Slash-command cheat sheet: shown while the draft starts with '/', until the
  // user dismisses it (Close / Esc) or leaves slash mode.
  const [slashDismissed, setSlashDismissed] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const showSlash = draft.trimStart().startsWith('/') && !slashDismissed;

  const refresh = useCallback(async () => {
    const s = await api.get<ChatState>('/api/chat/state');
    setState(s);
    setToolsBump((b) => b + 1);
  }, []);

  useEffect(() => {
    void refresh();
    const socket = new ChatSocket((e) => {
      if (e.event === 'token' && e.data) {
        setStreaming((prev) => prev + e.data);
      } else if (e.event === 'done' || e.event === 'error') {
        setStreaming('');
        void refresh();
      } else if (e.event === 'chat_updated' || e.event === 'generating') {
        void refresh();
      }
    });
    socket.connect();
    return () => socket.close();
  }, [refresh]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight });
  }, [state?.messages.length, streaming]);

  // Esc closes the open drawer or cancels an in-progress edit (desktop expectation).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if (editIndex !== null) setEditIndex(null);
      else if (showStats) setShowStats(false);
      else if (showSessions) setShowSessions(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editIndex, showStats, showSessions]);

  const send = async () => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    setSlashDismissed(false);
    await api.post('/api/chat/send', { text });
    await refresh();
  };

  const stop = () => api.post('/api/chat/stop');
  const regenerate = async () => {
    await api.post('/api/chat/regenerate');
    await refresh();
  };
  const continueGen = async () => {
    await api.post('/api/chat/continue');
    await refresh();
  };
  const swipe = async (messageIndex: number, direction: number) => {
    await api.post('/api/chat/swipe', { messageIndex, direction });
    await refresh();
  };
  const del = async (index: number) => {
    await api.post('/api/chat/delete', { index });
    await refresh();
  };
  const beginEdit = (m: Message) => {
    setEditIndex(m.index);
    setEditDraft(m.text);
  };
  const saveEdit = async () => {
    if (editIndex === null) return;
    const index = editIndex;
    setEditIndex(null);
    await api.post('/api/chat/edit', { index, text: editDraft });
    await refresh();
  };
  const saveAuthorNote = async (note: string, strength: number) => {
    await api.post('/api/chat/author-note', { authorNote: note, strength });
    await refresh();
  };

  // ── Conversations drawer ────────────────────────────────────────
  const openSessions = async () => {
    setShowSessions(true);
    setLoadingSessions(true);
    try {
      const r = await api.get<{ sessions: SessionSummary[] }>('/api/chat/sessions');
      setSessions(r.sessions ?? []);
    } catch {
      setSessions([]);
    } finally {
      setLoadingSessions(false);
    }
  };
  const loadSession = async (sessionId: string) => {
    setShowSessions(false);
    await api.post('/api/chat/session', { sessionId });
    await refresh();
  };
  const newChat = async () => {
    setShowSessions(false);
    await api.post('/api/chat/session', { action: 'new' });
    await refresh();
  };

  const formatDate = (iso: string) => {
    const d = new Date(iso);
    return Number.isNaN(d.getTime())
      ? ''
      : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  };

  if (!state) return <div className="centered"><div className="spinner" /></div>;

  if (!state.character) {
    return (
      <div className="page centered-col">
        <p className="muted">No character selected.</p>
        <button className="primary" onClick={() => navigate('/')}>
          Choose a character
        </button>
      </div>
    );
  }

  const lastIndex = state.messages.length - 1;
  const insight = state.realism ? (
    <Insight
      realism={state.realism}
      lorebook={state.lorebook}
      authorNote={state.authorNote ?? ''}
      authorNoteDepth={state.authorNoteDepth ?? 4}
      onSaveAuthorNote={saveAuthorNote}
      characterId={state.character.id}
      expressionLabel={state.expressionLabel}
      isGroup={state.isGroupMode ?? false}
      toolsKey={toolsBump}
    />
  ) : null;

  return (
    <div className="chat-layout">
      <div className="chat-view">
        <div className="chat-header">
          <div className="chat-header-id">
            {!state.isGroupMode && (
              <ExpressionPortrait
                characterId={state.character.id}
                expressionLabel={state.expressionLabel}
                className="chat-header-avatar"
              />
            )}
            <span className="chat-title">{state.character.name}</span>
          </div>
          <div className="chat-header-actions">
            {!state.isGroupMode && (
              <button
                className="link-btn"
                title="Edit character"
                onClick={() => navigate(`/edit/${state.character!.id}`)}
              >
                ✎
              </button>
            )}
            {insight && (
              <button className="link-btn stats-btn" onClick={() => setShowStats(true)}>
                Stats ▾
              </button>
            )}
            <button className="link-btn conversations-btn" onClick={openSessions}>
              Conversations ▾
            </button>
          </div>
        </div>

        <div className="chat-messages" ref={scrollRef}>
          {state.messages.map((m) => (
            <div key={m.index} className="msg-row">
              {m.hasThinking && m.thinkingContent && (
                <details className="thinking">
                  <summary>💭 Thoughts</summary>
                  <div className="thinking-body">{m.thinkingContent}</div>
                </details>
              )}
              {editIndex === m.index ? (
                <div className="msg-edit">
                  <textarea
                    value={editDraft}
                    onChange={(e) => setEditDraft(e.target.value)}
                    rows={4}
                    autoFocus
                  />
                  <div className="msg-edit-actions">
                    <button onClick={() => setEditIndex(null)}>Cancel</button>
                    <button className="primary" onClick={saveEdit}>Save</button>
                  </div>
                </div>
              ) : (
                <>
                  <div className={m.isUser ? 'bubble user' : 'bubble ai'}>{m.text}</div>
                  {!m.isUser && m.chips && <ChipsRow chips={m.chips} />}
                  <MessageActions
                    m={m}
                    isLast={m.index === lastIndex}
                    busy={state.isGenerating}
                    onSwipe={swipe}
                    onRegenerate={regenerate}
                    onContinue={continueGen}
                    onEdit={() => beginEdit(m)}
                    onDelete={() => del(m.index)}
                  />
                </>
              )}
            </div>
          ))}
          {streaming && <div className="bubble ai streaming">{streaming}</div>}
        </div>

        <div className="chat-input">
          {showSlash && (
            <div className="slash-cheatsheet" role="listbox" aria-label="Chat commands">
              <div className="cheatsheet-head">
                <span>Chat commands</span>
                <button className="link-btn" onClick={() => setSlashDismissed(true)}>Close</button>
              </div>
              {SLASH_COMMANDS.map((c) => (
                <button
                  key={c.cmd}
                  className="cheatsheet-row"
                  onClick={() => {
                    setDraft(c.args ? `${c.cmd} ` : c.cmd);
                    setSlashDismissed(true);
                  }}
                >
                  <span className="cheatsheet-cmd">
                    {c.cmd}{c.args && <span className="muted"> {c.args}</span>}
                  </span>
                  <span className="cheatsheet-desc">{c.desc}</span>
                </button>
              ))}
            </div>
          )}
          <textarea
            value={draft}
            onChange={(e) => {
              const v = e.target.value;
              setDraft(v);
              if (!v.trimStart().startsWith('/')) setSlashDismissed(false);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Escape' && showSlash) {
                e.preventDefault();
                setSlashDismissed(true);
                return;
              }
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                void send();
              }
            }}
            placeholder="Message…"
            rows={1}
          />
          {state.isGenerating ? (
            <button className="primary" onClick={stop}>Stop</button>
          ) : (
            <button className="primary" onClick={send} disabled={!draft.trim()}>
              Send
            </button>
          )}
        </div>
      </div>

      {/* Persistent insight column on desktop (CSS-hidden on phones). */}
      {insight && <aside className="chat-aside">{insight}</aside>}

      {/* Insight as a slide-over drawer on phones. */}
      {showStats && insight && (
        <div className="drawer-backdrop" onClick={() => setShowStats(false)}>
          <div className="sessions-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Chat insight</span>
              <button className="link-btn" onClick={() => setShowStats(false)}>Close</button>
            </div>
            {insight}
          </div>
        </div>
      )}

      {showSessions && (
        <div className="drawer-backdrop" onClick={() => setShowSessions(false)}>
          <div className="sessions-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Conversations</span>
              <button className="link-btn" onClick={() => setShowSessions(false)}>Close</button>
            </div>
            <button className="primary new-chat" onClick={newChat}>+ New chat</button>
            {loadingSessions ? (
              <div className="centered"><div className="spinner" /></div>
            ) : sessions.length === 0 ? (
              <p className="muted">No past conversations yet.</p>
            ) : (
              <ul className="conv-list">
                {sessions.map((s) => (
                  <li key={s.id}>
                    <button
                      className={`conv-item${s.id === state.sessionId ? ' active' : ''}`}
                      onClick={() => loadSession(s.id)}
                    >
                      <span className="conv-preview">{s.session_name || s.preview}</span>
                      <span className="conv-meta">
                        {formatDate(s.date)} · {s.message_count} msgs
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

/** Per-message action toolbar (swipe / regenerate / continue / edit / delete). */
function MessageActions({
  m,
  isLast,
  busy,
  onSwipe,
  onRegenerate,
  onContinue,
  onEdit,
  onDelete,
}: {
  m: Message;
  isLast: boolean;
  busy: boolean;
  onSwipe: (index: number, direction: number) => void;
  onRegenerate: () => void;
  onContinue: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  const count = m.swipeCount ?? 1;
  const idx = (m.swipeIndex ?? 0) + 1;
  const canSwipe = !m.isUser && (count > 1 || isLast);
  return (
    <div className={`msg-actions${m.isUser ? ' user' : ''}`}>
      {canSwipe && (
        <span className="swipe">
          <button className="icon-btn" title="Previous" disabled={busy}
            onClick={() => onSwipe(m.index, -1)}>◀</button>
          <span className="swipe-count">{idx}/{Math.max(count, idx)}</span>
          <button className="icon-btn" title="Next / new swipe" disabled={busy}
            onClick={() => onSwipe(m.index, 1)}>▶</button>
        </span>
      )}
      {!m.isUser && isLast && (
        <>
          <button className="icon-btn" title="Regenerate" disabled={busy} onClick={onRegenerate}>⟳</button>
          <button className="icon-btn" title="Continue" disabled={busy} onClick={onContinue}>⏩</button>
        </>
      )}
      <button className="icon-btn" title="Edit" disabled={busy} onClick={onEdit}>✎</button>
      <button className="icon-btn" title="Delete" disabled={busy} onClick={onDelete}>🗑</button>
    </div>
  );
}

const NEED_LABELS: Record<string, string> = {
  hunger: 'Hunger',
  bladder: 'Bladder',
  energy: 'Energy',
  social: 'Social',
  fun: 'Fun',
  hygiene: 'Hygiene',
  comfort: 'Comfort',
};

/** Per-message Realism chips shown under an AI reply. */
function ChipsRow({ chips }: { chips: Chips }) {
  const pills: { label: string; cls: string }[] = [];
  const signed = (n: number) => (n > 0 ? `+${n}` : `${n}`);
  if (chips.bondDelta) pills.push({ label: `Bond ${signed(chips.bondDelta)}`, cls: chips.bondDelta > 0 ? 'up' : 'down' });
  if (chips.trustDelta) pills.push({ label: `Trust ${signed(chips.trustDelta)}`, cls: chips.trustDelta > 0 ? 'up' : 'down' });
  if (chips.arousalDelta) pills.push({ label: `Arousal ${signed(chips.arousalDelta)}`, cls: chips.arousalDelta > 0 ? 'up' : 'down' });
  if (chips.emotionLabel) pills.push({ label: chips.emotionLabel, cls: 'mood' });
  if (chips.timeSkipTo) pills.push({ label: `⏱ ${chips.timeSkipTo}`, cls: 'time' });
  if (chips.chanceTimeEvent) pills.push({ label: `🎲 ${chips.chanceTimeEvent}`, cls: 'time' });
  for (const [k, v] of Object.entries(chips.needsDeltas ?? {})) {
    pills.push({ label: `${NEED_LABELS[k] ?? k} ${signed(v)}`, cls: v > 0 ? 'up' : 'down' });
  }
  if (pills.length === 0) return null;
  return (
    <div className="chips-row">
      {pills.map((p, i) => (
        <span key={i} className={`chip ${p.cls}`}>{p.label}</span>
      ))}
    </div>
  );
}

/** Character portrait that prefers the mood-driven expression avatar and falls
 *  back to the static card avatar. The `expressionLabel` cache-busts the image
 *  so the portrait swaps when the active emotion changes (on `chat_updated`). */
function ExpressionPortrait({
  characterId,
  expressionLabel,
  className,
}: {
  characterId: string;
  expressionLabel?: string;
  className: string;
}) {
  const expr = `/api/chat/expression-avatar?v=${encodeURIComponent(expressionLabel ?? '')}`;
  const fallback = `/api/characters/${characterId}/avatar`;
  const [src, setSrc] = useState(expr);
  useEffect(() => setSrc(expr), [expr]);
  return (
    <img
      className={className}
      src={src}
      alt=""
      onError={() => {
        if (src !== fallback) setSrc(fallback);
      }}
    />
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

/** Realism + lorebook + author-note panel (drawer on phone, sidebar on desktop). */
function Insight({
  realism,
  lorebook,
  authorNote,
  authorNoteDepth,
  onSaveAuthorNote,
  characterId,
  expressionLabel,
  isGroup,
  toolsKey,
}: {
  realism: Realism;
  lorebook?: LoreEntry[];
  authorNote: string;
  authorNoteDepth: number;
  onSaveAuthorNote: (note: string, strength: number) => void;
  characterId: string;
  expressionLabel?: string;
  isGroup: boolean;
  toolsKey: number;
}) {
  const [note, setNote] = useState(authorNote);
  useEffect(() => setNote(authorNote), [authorNote]);
  return (
    <div className="realism-panel">
      {!isGroup && (
        <div className="portrait-wrap">
          <ExpressionPortrait
            characterId={characterId}
            expressionLabel={expressionLabel}
            className="portrait"
          />
          {(realism.mood || realism.emotion) && (
            <span className="portrait-mood">{realism.mood || realism.emotion}</span>
          )}
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
      {realism.fixation && (
        <div className="stat-line"><span>Fixation</span><span className="muted">{realism.fixation}</span></div>
      )}
      {realism.needsEnabled && Object.keys(realism.needs).length > 0 && (
        <>
          <h4 className="section-label">Needs</h4>
          {Object.entries(realism.needs).map(([k, v]) => (
            <StatBar key={k} label={NEED_LABELS[k] ?? k} value={`${v}`} percent={v}
              tone={v < 25 ? 'danger' : v < 50 ? 'warn' : ''} />
          ))}
        </>
      )}

      <ChatTools reloadKey={toolsKey} />

      <h4 className="section-label">Author's note</h4>
      <textarea
        className="note-input"
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Steer the narrative (injected near the end of context)…"
        rows={3}
      />
      <button className="primary note-save" onClick={() => onSaveAuthorNote(note, authorNoteDepth)}>
        Save note
      </button>

      {lorebook && lorebook.length > 0 && (
        <>
          <h4 className="section-label">Lorebook</h4>
          <ul className="lore-list">
            {lorebook.map((e, i) => (
              <li key={i} className={e.isTriggered ? 'lore on' : 'lore'}>
                <span className="lore-dot" />
                <span>{e.name}{e.constant ? ' · always' : ''}</span>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}
