// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import { CastBar, type CastMember } from '../components/CastBar';
import { CharacterPicker } from '../components/CharacterPicker';
import { ProcessingOverlay, NO_PROCESSING, type Processing } from '../components/ProcessingOverlay';
import { SmartImg } from '../components/ChatAvatar';
import { ChatMessageList } from '../components/ChatMessageList';
import { ChatComposer } from '../components/ChatComposer';
import { ChatInsight } from '../components/ChatInsight';
import { ConversationsDrawer, type SessionSummary } from '../components/ConversationsDrawer';
import { ReprocessNeedsModal } from '../components/ReprocessNeedsModal';
import { type Message, type Realism, type LoreEntry } from '../components/chatTypes';

interface ChatState {
  character: { name: string; id: string } | null;
  chatTitle?: string | null;
  sessionId: string | null;
  messages: Message[];
  isGenerating: boolean;
  isEvaluatingRealism?: boolean;
  isCheckingCompletion?: boolean;
  isProcessingGreeting?: boolean;
  isVerifyingRealism?: boolean;
  realismEvalText?: string;
  isGroupMode?: boolean;
  groupId?: string | null;
  realism?: Realism;
  lorebook?: LoreEntry[];
  authorNote?: string;
  authorNoteDepth?: number;
  greetingIndex?: number;
  totalGreetings?: number;
  expressionLabel?: string;
  cast?: CastMember[];
  guestActivity?: { status: string | null; isError: boolean; busy: boolean };
  pendingDetection?: string | null;
}

export function ChatPage() {
  const navigate = useNavigate();
  const [state, setState] = useState<ChatState | null>(null);
  const [streaming, setStreaming] = useState('');
  // Realism/Objective engine overlay, driven by the `processing` WS event.
  const [processing, setProcessing] = useState<Processing>(NO_PROCESSING);
  // Resizable insight sidebar (desktop) — width persists across sessions.
  const [asideWidth, setAsideWidth] = useState<number>(() => {
    const v = typeof localStorage !== 'undefined' ? localStorage.getItem('fpai.asideWidth') : null;
    const n = v ? parseInt(v, 10) : NaN;
    return Number.isFinite(n) ? Math.min(560, Math.max(260, n)) : 320;
  });
  const [showSessions, setShowSessions] = useState(false);
  const [showStats, setShowStats] = useState(false);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(false);
  const [editIndex, setEditIndex] = useState<number | null>(null);
  const [editDraft, setEditDraft] = useState('');
  // Director-redo (reprocess Needs) — only the target message index lives here;
  // the modal owns its own critique/busy/error state.
  const [reprocessIndex, setReprocessIndex] = useState<number | null>(null);
  // Bumps whenever chat state refreshes (incl. WS chat_updated) so the tools
  // sidebar refetches its own snapshot in lock-step.
  const [toolsBump, setToolsBump] = useState(0);
  // Unified-cast UI: which participant the sidebar is scoped to, the add-picker,
  // and the focused participant's realism (null = use the default host snapshot).
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [showPicker, setShowPicker] = useState(false);
  const [focusRealism, setFocusRealism] = useState<Realism | null>(null);
  // Voice capability snapshot (TTS on? STT usable?) — gates the Speak/Mic UI.
  const [voice, setVoice] = useState<{ ttsEnabled: boolean; sttAvailable: boolean } | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  // Coalesces bursts of `chat_updated` (a single turn fires several: send, guest
  // actions, realism chip-attach, …) into one refresh so the transcript doesn't
  // reload repeatedly while the engines work.
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const canMic = !!voice?.sttAvailable && typeof window !== 'undefined' && window.isSecureContext;

  const refresh = useCallback(async () => {
    const s = await api.get<ChatState>('/api/chat/state');
    setState(s);
    setToolsBump((b) => b + 1);
    // Safety net: if the engines are fully idle (and not generating), make sure
    // the processing overlay is dismissed even if its final WS event was missed
    // (e.g. a socket reconnect mid-eval). Never clears during an active eval —
    // refresh() doesn't run then (the `processing` event drives the overlay).
    if (!s.isEvaluatingRealism && !s.isCheckingCompletion && !s.isGenerating) {
      setProcessing(NO_PROCESSING);
    }
  }, []);

  // Trailing-debounced refresh for high-frequency `chat_updated` bursts: fires
  // ~80ms after the last event so a flurry collapses into a single re-render
  // (imperceptible delay; `done` and send() still refresh immediately).
  const scheduleRefresh = useCallback(() => {
    if (refreshTimer.current !== null) clearTimeout(refreshTimer.current);
    refreshTimer.current = setTimeout(() => {
      refreshTimer.current = null;
      void refresh();
    }, 80);
  }, [refresh]);

  // Cast actions and the composer share one send path (both route through
  // ChatService server-side, so behavior matches the desktop).
  const sendMessage = useCallback(async (text: string) => {
    const t = text.trim();
    if (!t) return;
    await api.post('/api/chat/send', { text: t });
    await refresh();
  }, [refresh]);

  // Scope the sidebar to a cast participant. Host (and lite guests) use the main
  // realism snapshot; other members fetch their own.
  const focusParticipant = useCallback(async (id: string) => {
    setFocusedId(id);
    const member = state?.cast?.find((c) => c.id === id);
    if (!member || member.isHost || !member.realismEnabled) {
      setFocusRealism(null);
      return;
    }
    try {
      setFocusRealism(await api.get<Realism>(`/api/chat/participant/${id}/realism`));
    } catch {
      setFocusRealism(null);
    }
  }, [state?.cast]);

  // Keep a focused member's realism live as the chat updates.
  useEffect(() => {
    if (focusedId) void focusParticipant(focusedId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [toolsBump]);

  useEffect(() => {
    void refresh();
    const socket = new ChatSocket((e) => {
      if (e.event === 'token' && e.data) {
        setStreaming((prev) => prev + e.data);
      } else if (e.event === 'done' || e.event === 'error') {
        // Refresh FIRST, then drop the live streaming bubble — so the finalized
        // message is already in state when the streaming bubble is removed. The
        // two are identical text, so it swaps seamlessly with no flash/gap (the
        // old order cleared the bubble, leaving the message blank until the GET
        // returned ~100-300ms later).
        void refresh().finally(() => setStreaming(''));
      } else if (e.event === 'processing') {
        setProcessing(
          e.active
            ? {
                active: true,
                realism: !!e.realism,
                objective: !!e.objective,
                greeting: !!e.greeting,
                verifying: !!e.verifying,
                text: e.text ?? '',
              }
            : NO_PROCESSING,
        );
      } else if (e.event === 'chat_updated' || e.event === 'generating') {
        scheduleRefresh();
      }
    });
    socket.connect();
    return () => {
      socket.close();
      if (refreshTimer.current !== null) clearTimeout(refreshTimer.current);
    };
  }, [refresh, scheduleRefresh]);

  useEffect(() => {
    api.get<{ ttsEnabled: boolean; sttAvailable: boolean }>('/api/voice/status')
      .then(setVoice)
      .catch(() => {});
  }, []);

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

  // Drag the insight sidebar's left edge to resize it (clamped 260–560px),
  // persisting the chosen width. Dragging left widens (handle is on the left).
  const startAsideResize = (e: ReactMouseEvent) => {
    e.preventDefault();
    const startX = e.clientX;
    const startW = asideWidth;
    const onMove = (ev: MouseEvent) => {
      setAsideWidth(Math.min(560, Math.max(260, startW + (startX - ev.clientX))));
    };
    const onUp = () => {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      setAsideWidth((w) => {
        try { localStorage.setItem('fpai.asideWidth', String(w)); } catch { /* ignore */ }
        return w;
      });
    };
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
  };

  const stop = () => api.post('/api/chat/stop');
  const cancelRealism = () => {
    setProcessing(NO_PROCESSING);
    void api.post('/api/chat/cancel-realism').catch(() => {});
  };
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

  // Director redo: reprocess a message's Needs deltas with a written critique
  // (throws on failure so the modal can surface the error), or revert.
  const submitReprocess = async (critique: string) => {
    if (reprocessIndex === null) return;
    await api.post('/api/chat/reprocess-needs', { index: reprocessIndex, critique });
    await refresh();
    setReprocessIndex(null);
  };
  const revertNeeds = async (index: number) => {
    await api.post('/api/chat/revert-needs-reprocess', { index });
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

  if (!state) return <div className="centered"><div className="spinner" /></div>;

  const cast = state.cast ?? [];
  // A chat is active if there's a cast (group or 1:1) or a host character.
  // (In a group, state.character is null — the cast carries the participants.)
  if (cast.length === 0 && !state.character) {
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
  const multiCast = cast.length > 1;
  // The focused participant (sidebar scope + header avatar); default to the
  // host, else the first cast member.
  const focused = cast.find((c) => c.id === focusedId) ?? cast.find((c) => c.isHost) ?? cast[0];
  const title = state.chatTitle || state.character?.name || 'Chat';
  // Editing targets a real library character — the 1:1 host or a scene guest,
  // never a group member (denormalized copies aren't web-editable).
  const editId = !state.isGroupMode ? focused?.dbId ?? state.character?.id : undefined;
  // Speaker lookup for per-message avatars/names in a multi-character scene.
  const castById = new Map(cast.map((c) => [c.id, c]));
  const realismForPanel = focusRealism ?? state.realism;
  const insight = realismForPanel ? (
    <ChatInsight
      realism={realismForPanel}
      lorebook={state.lorebook}
      authorNote={state.authorNote ?? ''}
      authorNoteDepth={state.authorNoteDepth ?? 4}
      onSaveAuthorNote={saveAuthorNote}
      characterId={focused?.dbId ?? state.character?.id ?? ''}
      expressionLabel={state.expressionLabel}
      isGroup={state.isGroupMode ?? false}
      focusedIsHost={focused?.isHost ?? !state.isGroupMode}
      focusedAvatarUrl={focused?.avatarUrl}
      toolsKey={toolsBump}
      focusedId={focusedId}
      groupId={state.groupId ?? null}
      onCommand={sendMessage}
      cast={cast}
      onFocus={focusParticipant}
    />
  ) : null;

  return (
    <div className="chat-layout">
      <div className="chat-view">
        <div className="chat-header">
          <div className="chat-header-id">
            {focused && (
              state.isGroupMode ? (
                // Groups have no single avatar and member images don't resolve in
                // the cast — show a group glyph rather than a broken image.
                <span className="chat-header-avatar group" aria-hidden>👥</span>
              ) : focused.isHost ? (
                <SmartImg
                  primary={`/api/chat/expression-avatar?v=${encodeURIComponent(state.expressionLabel ?? '')}`}
                  fallback={`/api/characters/${focused.dbId ?? state.character?.id ?? ''}/avatar`}
                  className="chat-header-avatar"
                />
              ) : (
                <SmartImg primary={focused.avatarUrl ?? ''} className="chat-header-avatar" />
              )
            )}
            <span className="chat-title">{title}</span>
          </div>
          <div className="chat-header-actions">
            {editId && (
              <button
                className="link-btn"
                title="Edit character"
                onClick={() => navigate(`/edit/${editId}`)}
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

        <CastBar
          cast={cast}
          focusedId={focusedId}
          busy={state.isGenerating}
          guestStatus={state.guestActivity?.status ?? null}
          guestIsError={state.guestActivity?.isError ?? false}
          pendingDetection={state.pendingDetection ?? null}
          onFocus={focusParticipant}
          onAdd={() => setShowPicker(true)}
          onCommand={sendMessage}
        />

        <ChatMessageList
          messages={state.messages}
          castById={castById}
          multiCast={multiCast}
          lastIndex={lastIndex}
          busy={state.isGenerating}
          streaming={streaming}
          scrollRef={scrollRef}
          canSpeak={!!voice?.ttsEnabled}
          editIndex={editIndex}
          editDraft={editDraft}
          onEditDraftChange={setEditDraft}
          onCancelEdit={() => setEditIndex(null)}
          onSaveEdit={saveEdit}
          onBeginEdit={beginEdit}
          onSwipe={swipe}
          onRegenerate={regenerate}
          onContinue={continueGen}
          onDelete={del}
          onReprocess={setReprocessIndex}
          onRevert={revertNeeds}
        />

        <ProcessingOverlay p={processing} onCancel={cancelRealism} />

        <ChatComposer
          onSend={sendMessage}
          onStop={stop}
          isGenerating={state.isGenerating}
          canMic={canMic}
        />
      </div>

      {showPicker && (
        <CharacterPicker
          onPick={(name, full) => {
            void sendMessage(`/join ${full ? '--full ' : ''}${name}`);
            setShowPicker(false);
          }}
          onClose={() => setShowPicker(false)}
        />
      )}

      {/* Persistent insight column on desktop (CSS-hidden on phones). */}
      {insight && (
        <aside className="chat-aside" style={{ width: asideWidth }}>
          <div className="aside-resizer" onMouseDown={startAsideResize} title="Drag to resize" />
          {insight}
        </aside>
      )}

      {/* Insight as a slide-over drawer on phones. */}
      {showStats && insight && (
        <div className="drawer-backdrop" onClick={() => setShowStats(false)}>
          <div className="sessions-drawer stats-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Chat insight</span>
              <button className="link-btn" onClick={() => setShowStats(false)}>Close</button>
            </div>
            {insight}
          </div>
        </div>
      )}

      {reprocessIndex !== null && (
        <ReprocessNeedsModal
          onSubmit={submitReprocess}
          onClose={() => setReprocessIndex(null)}
        />
      )}

      {showSessions && (
        <ConversationsDrawer
          sessions={sessions}
          loading={loadingSessions}
          activeSessionId={state.sessionId}
          onLoad={loadSession}
          onNew={newChat}
          onClose={() => setShowSessions(false)}
        />
      )}
    </div>
  );
}
