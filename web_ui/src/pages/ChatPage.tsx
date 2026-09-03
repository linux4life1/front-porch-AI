// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { api } from '../api/client';
import { ChatSocket } from '../api/ws';
import { CastBar, type CastMember } from '../components/CastBar';
import { CharacterPicker } from '../components/CharacterPicker';
import { ProcessingOverlay, NO_PROCESSING, type Processing } from '../components/ProcessingOverlay';
import { SmartImg } from '../components/ChatAvatar';
import { ChatMessageList, type GenStatus } from '../components/ChatMessageList';
import { ChatComposer } from '../components/ChatComposer';
import { ChatInsight } from '../components/ChatInsight';
import { ConversationsDrawer, type SessionSummary } from '../components/ConversationsDrawer';
import { ReprocessNeedsModal } from '../components/ReprocessNeedsModal';
import { ChatPersonaModal } from '../components/ChatPersonaModal';
import { ChanceTimeModal } from '../components/ChanceTimeModal';
import { ImagePromptReviewModal } from '../components/ImagePromptReviewModal';
import { MessageEditModal } from '../components/MessageEditModal';
import { type Message, type Realism, type LoreEntry, type ChatThemeOverrides } from '../components/chatTypes';
import { ChatThemeSettings, resolveThemeColors } from '../components/ChatThemeSettings';
import { postChatSend } from './chatSend';
import { describeChatLoadFailure } from './chatLoad';
import { useAuth } from '../auth/AuthContext';
import { useLayout } from '../hooks/useBreakpoint';

interface ChatState {
  character: { name: string; id: string } | null;
  chatTitle?: string | null;
  sessionId: string | null;
  messages: Message[];
  isGenerating: boolean;
  isSettlingTurn?: boolean;
  isSendWaitingOnSettle?: boolean;
  isLoadingSession?: boolean;
  isBackfillingHistory?: boolean;
  hasOlderHistory?: boolean;
  isEvaluatingRealism?: boolean;
  isCheckingCompletion?: boolean;
  isProcessingGreeting?: boolean;
  isVerifyingRealism?: boolean;
  realismEvalText?: string;
  isGroupMode?: boolean;
  groupId?: string | null;
  realism?: Realism;
  lorebook?: LoreEntry[];
  loreTokens?: number;
  loreBudget?: number;
  loreOverflow?: string[];
  authorNote?: string;
  authorNoteDepth?: number;
  greetingIndex?: number;
  totalGreetings?: number;
  expressionLabel?: string;
  // Living Time §2 welcome-back banner (additive — absent on older facades;
  // null when off/under threshold). Coarse words only.
  absencePhrase?: string | null;
  summary?: string;
  cast?: CastMember[];
  guestActivity?: { status: string | null; isError: boolean; busy: boolean };
  pendingDetection?: string | null;
  // Chaos "Chance Time" park state: while pending, the engine is frozen waiting
  // for the user to accept their fate (event is pre-resolved server-side).
  chanceTime?: { pending: boolean; event?: string };
  // Crafted /image prompt parked for review (review setting on) — the modal
  // resolves it via POST /api/chat/image-review.
  imagePromptReview?: string;
  // Current model's tool-calling verdict (desktop sidebar pill parity);
  // retest via POST /api/chat/tool-test.
  toolSupport?: {
    state: string;
    testing: boolean;
    preferText?: boolean;
    paused?: boolean;
    checked?: boolean;
  };
  // Per-chat theme overrides (preset + font/color/background/border).
  themeOverrides?: ChatThemeOverrides;
  // Host LLM connection (additive — older desktops omit it).
  llmReady?: boolean;
}

export function ChatPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const opening = searchParams.get('opening') === '1';
  const { setAuthenticated } = useAuth();
  // The insight column is desktop-only (CSS hides it below 1024px) and the
  // Stats drawer is its phone/tablet stand-in — mount whichever one is on
  // screen. `display:none` does not unmount, so rendering both meant every
  // chat refresh fired the sidebar's GETs (tools / journal / growth / places)
  // for a panel nobody could see, twice over with the drawer open.
  const { isDesktop } = useLayout();
  const [state, setState] = useState<ChatState | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const tokenSessionRef = useRef<string | null>(null);
  // Why the chat could not be loaded — shown instead of a spinner that would
  // otherwise never resolve.
  const [loadError, setLoadError] = useState('');
  const [streaming, setStreaming] = useState('');
  // Living Time §2: sessions whose welcome-back banner was dismissed (ephemeral).
  const [absenceDismissed, setAbsenceDismissed] = useState<Set<string>>(new Set());
  // Composer draft mirror — powers the lorebook "would trigger next" preview.
  const [draft, setDraft] = useState('');
  // A send that never reached the desktop: the exact text the user typed (the
  // composer already threw its copy away) plus a plain-English reason.
  const [sendError, setSendError] = useState<
    { text: string; message: string; retrying: boolean } | null
  >(null);
  // Chaos "Chance Time" reveal modal. Opened by the `chance_time` WS event (or a
  // reconnect that finds the engine still parked); `revealed` is the pure-UI
  // flip from the teaser to the event card. Null = no modal.
  const [chance, setChance] = useState<{ event: string; revealed: boolean } | null>(null);
  // Live image-gen progress (from the `image_progress` WS event): percent
  // (null = indeterminate) + the latest preview frame data URL when the
  // backend streams one. Null = no image generating.
  const [imageProg, setImageProg] = useState<{ progress: number | null; preview: string | null } | null>(null);
  const [genStatus, setGenStatus] = useState<GenStatus | null>(null);
  // Realism/Objective engine overlay, driven by the `processing` WS event.
  const [processing, setProcessing] = useState<Processing>(NO_PROCESSING);
  // Resizable insight sidebar (desktop) — width persists across sessions.
  const [asideWidth, setAsideWidth] = useState<number>(() => {
    const v = typeof localStorage !== 'undefined' ? localStorage.getItem('fpai.asideWidth') : null;
    const n = v ? parseInt(v, 10) : NaN;
    return Number.isFinite(n) ? Math.min(560, Math.max(260, n)) : 320;
  });
  const [showSessions, setShowSessions] = useState(false);
  const [importNotice, setImportNotice] = useState('');
  const [showStats, setShowStats] = useState(false);
  const [showTheme, setShowTheme] = useState(false);
  const [showPersona, setShowPersona] = useState(false);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(false);
  // Fullscreen message editor — index + original text while the modal is open.
  const [editTarget, setEditTarget] = useState<{ index: number; text: string } | null>(null);
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
  // Live Impersonate composer fill (dedicated WS event — not the AI bubble).
  const [impersonateFill, setImpersonateFill] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  // Coalesces bursts of `chat_updated` (a single turn fires several: send, guest
  // actions, realism chip-attach, …) into one refresh so the transcript doesn't
  // reload repeatedly while the engines work.
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const canMic = !!voice?.sttAvailable && typeof window !== 'undefined' && window.isSecureContext;

  const refresh = useCallback(async () => {
    let s: ChatState;
    try {
      s = await api.get<ChatState>('/api/chat/state');
    } catch (e) {
      // Never rethrow: every caller fires this and walks away, so a rejection
      // here used to be an unhandled promise AND a permanent spinner.
      const failure = describeChatLoadFailure(e);
      if (failure.signedOut) setAuthenticated(false);
      else console.warn('[chat] state refresh failed', e);
      setLoadError(failure.message);
      return;
    }
    setLoadError('');
    setState(s);
    sessionIdRef.current = s.sessionId;
    // Recover the Chance Time modal after a reconnect — a phone may have slept
    // through the live `chance_time` event while the engine stayed parked.
    // Preserve an already-open modal's reveal state; close it once unparked.
    setChance((c) =>
      s.chanceTime?.pending ? c ?? { event: s.chanceTime.event ?? '', revealed: false } : null,
    );
    setToolsBump((b) => b + 1);
    // Safety net: if the engines are fully idle (and not generating), make sure
    // the processing overlay is dismissed even if its final WS event was missed
    // (e.g. a socket reconnect mid-eval). Never clears during an active eval —
    // refresh() doesn't run then (the `processing` event drives the overlay).
    if (!s.isEvaluatingRealism && !s.isCheckingCompletion && !s.isGenerating) {
      setProcessing(NO_PROCESSING);
    }
  }, [setAuthenticated]);

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
  // ChatService server-side, so behavior matches the desktop). The composer has
  // already emptied its box by the time we're called, so a failed POST must
  // hand the typed text back to the user (sendError) instead of dropping it —
  // on a phone over Tailscale a blipped uplink used to eat the message with no
  // trace at all. Never rethrows, so the `void sendMessage(...)` call sites
  // (CastBar commands, the /join picker) can't strand a rejected promise.
  const sendMessage = useCallback(async (text: string) => {
    const t = text.trim();
    if (!t) return;
    const outcome = await postChatSend(t);
    if (!outcome.ok) {
      setSendError({ text: outcome.text, message: outcome.message, retrying: false });
      return;
    }
    setSendError(null);
    // The line is in ChatService now — a failed refresh loses nothing (the WS
    // `chat_updated` burst re-renders anyway), so it must NOT offer a resend.
    await refresh().catch((e) => console.warn('[chat] refresh after send failed', e));
  }, [refresh]);

  // Resend the message the last failure handed back (one tap, no retyping).
  const retrySend = async () => {
    const failed = sendError;
    if (!failed || failed.retrying) return;
    setSendError({ ...failed, retrying: true });
    await sendMessage(failed.text);
  };

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

  const wasOpening = useRef(false);
  useEffect(() => {
    if (opening) {
      wasOpening.current = true;
      return;
    }
    if (wasOpening.current) {
      wasOpening.current = false;
      void refresh();
    }
  }, [opening, refresh]);

  useEffect(() => {
    if (!state?.isBackfillingHistory) return;
    const t = setTimeout(() => {
      void refresh();
    }, 120);
    return () => clearTimeout(t);
  }, [state?.isBackfillingHistory, state?.messages.length, refresh]);

  useEffect(() => {
    void refresh();
    const socket = new ChatSocket((e) => {
      if (e.event === 'impersonate' && typeof e.data === 'string') {
        setImpersonateFill(e.data);
      } else if (e.event === 'impersonate_done') {
        setImpersonateFill(null);
        void refresh();
      } else if (e.event === 'token' && e.data) {
        if (!tokenSessionRef.current) {
          tokenSessionRef.current = sessionIdRef.current;
        }
        if (
          tokenSessionRef.current &&
          sessionIdRef.current &&
          tokenSessionRef.current !== sessionIdRef.current
        ) {
          return;
        }
        setStreaming((prev) => prev + e.data);
      } else if (e.event === 'done' || e.event === 'error') {
        // Refresh FIRST, then drop the live streaming bubble — so the finalized
        // message is already in state when the streaming bubble is removed. The
        // two are identical text, so it swaps seamlessly with no flash/gap (the
        // old order cleared the bubble, leaving the message blank until the GET
        // returned ~100-300ms later).
        setGenStatus(null);
        void refresh().finally(() => {
          setStreaming('');
          tokenSessionRef.current = null;
        });
      } else if (e.event === 'gen_status') {
        // Truthful generation status (desktop status-bar parity): live
        // prompt-reading progress + which background pass holds the slot.
        // Returning the previous object when nothing changed lets React bail
        // out of the re-render — these frames arrive ~2.5/s for whole turns.
        setGenStatus((prev) => {
          if (!e.active) return null;
          const next = {
            phase: e.phase ?? '',
            busyWith: e.busyWith ?? null,
            queued: e.queued ?? 0,
            promptCur: e.promptCur ?? null,
            promptTotal: e.promptTotal ?? null,
            promptDone: !!e.promptDone,
            estFraction: e.estFraction ?? null,
            genCur: e.genCur ?? null,
            genTotal: e.genTotal ?? null,
          };
          return prev &&
            prev.phase === next.phase &&
            prev.busyWith === next.busyWith &&
            prev.queued === next.queued &&
            prev.promptCur === next.promptCur &&
            prev.promptTotal === next.promptTotal &&
            prev.promptDone === next.promptDone &&
            prev.estFraction === next.estFraction &&
            prev.genCur === next.genCur &&
            prev.genTotal === next.genTotal
            ? prev
            : next;
        });
      } else if (e.event === 'processing') {
        // Same bail-out treatment: the server already throttles these, but a
        // reconnect or an old server can still deliver identical payloads.
        setProcessing((prev) => {
          if (!e.active) return NO_PROCESSING;
          const next = {
            active: true,
            realism: !!e.realism,
            objective: !!e.objective,
            greeting: !!e.greeting,
            verifying: !!e.verifying,
            text: (e.text ?? '') as string,
          };
          return prev.active === next.active &&
            prev.realism === next.realism &&
            prev.objective === next.objective &&
            prev.greeting === next.greeting &&
            prev.verifying === next.verifying &&
            prev.text === next.text
            ? prev
            : next;
        });
      } else if (e.event === 'chance_time') {
        // Chaos parked the send waiting for "accept your fate". Pop the reveal
        // modal instantly (desktop shows its own wheel); `pending:false` closes
        // it — e.g. the desktop, or another device, accepted first.
        setChance(e.pending ? { event: e.data ?? '', revealed: false } : null);
      } else if (e.event === 'image_progress') {
        // Live image generation: percent + (when the backend streams one) the
        // in-progress preview frame — the picture forms in the card below the
        // messages instead of a black-box wait. Desktop bubble parity.
        setImageProg(
          e.generating
            ? (prev) => ({
                progress: typeof e.progress === 'number' ? e.progress : null,
                preview: (e.preview as string | undefined) ?? prev?.preview ?? null,
              })
            : null,
        );
      } else if (e.event === 'chat_updated' || e.event === 'generating') {
        scheduleRefresh();
      } else if (e.event === 'connected') {
        // (Re)connected. The socket may have been down (phone sleep, network
        // blip) while the desktop finished a generation or edited the chat, so
        // events were missed — refetch to heal. Also drop any stale partial
        // streaming buffer: if a `done` was missed, the leftover partial would
        // render as a ghost bubble AND the next generation would append onto
        // it (setStreaming(prev => prev + …)), garbling the live reply.
        // Same for the gen-status bubble — a missed {active:false} would
        // strand it forever.
        setStreaming('');
        setGenStatus(null);
        void refresh();
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

  // Esc closes drawers (message edit owns its own Esc + dirty confirm).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      if (editTarget) return; // MessageEditModal handles Escape
      if (showStats) setShowStats(false);
      else if (showSessions) setShowSessions(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [editTarget, showStats, showSessions]);

  // Apply per-chat theme overrides as CSS custom properties on the chat container.
  useEffect(() => {
    const vars = resolveThemeColors(state?.themeOverrides ?? null);
    const el = document.querySelector('.chat-view') as HTMLElement | null;
    if (!el) return;
    Object.entries(vars).forEach(([k, v]) => el.style.setProperty(k, v));
    // Only veil the chat when a theme actually supplies a background scene.
    el.classList.toggle('has-theme-bg', '--chat-bg-image' in vars);
    return () => {
      Object.keys(vars).forEach((k) => el.style.removeProperty(k));
      el.classList.remove('has-theme-bg');
    };
  }, [state?.themeOverrides]);

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
  // Chance Time: flip the teaser to the event card, then accept — which unfreezes
  // the parked send server-side so the reply streams in (close optimistically).
  const revealFate = () => setChance((c) => (c ? { ...c, revealed: true } : c));
  const acceptFate = async () => {
    const pending = chance;
    setChance(null);
    try {
      await api.post('/api/chat/chance-time/accept');
    } catch {
      // Network hiccup — reopen so the still-parked send can be resolved.
      if (pending) setChance(pending);
    }
  };
  const cancelRealism = () => {
    setProcessing(NO_PROCESSING);
    void api.post('/api/chat/cancel-realism').catch(() => {});
  };
  // The transcript handlers are useCallback-stable so token/processing WS
  // frames (which re-render this page many times a second during a turn)
  // never invalidate the memoized transcript rows — see TranscriptRows.
  const regenerate = useCallback(async () => {
    await api.post('/api/chat/regenerate');
    await refresh();
  }, [refresh]);
  const continueGen = useCallback(async () => {
    await api.post('/api/chat/continue');
    await refresh();
  }, [refresh]);
  const fork = useCallback(async (index: number) => {
    if (
      !window.confirm(
        `Create a new branch from message #${index + 1}?\n\nThe current chat will remain unchanged. A new conversation will be created with messages up to this point.`,
      )
    ) {
      return;
    }
    await api.post('/api/chat/fork', { index });
    await refresh();
  }, [refresh]);
  const swipe = useCallback(async (messageIndex: number, direction: number) => {
    await api.post('/api/chat/swipe', { messageIndex, direction });
    await refresh();
  }, [refresh]);
  const del = useCallback(async (index: number) => {
    await api.post('/api/chat/delete', { index });
    await refresh();
  }, [refresh]);
  const beginEdit = useCallback((m: Message) => {
    setEditTarget({ index: m.index, text: m.text });
  }, []);
  const saveEdit = async (text: string) => {
    if (!editTarget) return;
    const index = editTarget.index;
    setEditTarget(null);
    await api.post('/api/chat/edit', { index, text });
    await refresh();
  };
  const saveAuthorNote = async (note: string, strength: number) => {
    await api.post('/api/chat/author-note', { authorNote: note, strength });
    await refresh();
  };
  const saveTheme = async (overrides: ChatThemeOverrides) => {
    await api.post('/api/chat/theme-overrides', overrides);
    setShowTheme(false);
    await refresh();
  };

  // Director redo: reprocess a message's Needs deltas with a written critique
  // (throws on failure so the modal can surface the error), or revert.
  const submitReprocess = async (critique: string, onlyNeeds: string[]) => {
    if (reprocessIndex === null) return;
    // 'needs' omitted when nothing was selected — the server treats a missing
    // key as "all needs", which is also what older builds send.
    await api.post('/api/chat/reprocess-needs', {
      index: reprocessIndex,
      critique,
      ...(onlyNeeds.length > 0 ? { needs: onlyNeeds } : {}),
    });
    await refresh();
    setReprocessIndex(null);
  };
  const revertNeeds = useCallback(async (index: number) => {
    await api.post('/api/chat/revert-needs-reprocess', { index });
    await refresh();
  }, [refresh]);

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
  // Switching chats abandons whatever the old one was doing on screen. The
  // server may still be finishing that generation (its settle wait gives up
  // after 15s), and its tokens keep arriving on the shared socket — without
  // this the previous character's half-written reply stayed on screen as a
  // live bubble under the NEW conversation and kept growing. Same reasoning as
  // the `connected` handler above; the chance-time modal belongs to the chat
  // being left, too.
  const clearLiveTurnUi = () => {
    setStreaming('');
    setGenStatus(null);
    setImageProg(null);
    setChance(null);
    tokenSessionRef.current = null;
  };
  const loadSession = async (sessionId: string) => {
    setShowSessions(false);
    clearLiveTurnUi();
    await api.post('/api/chat/session', { sessionId });
    await refresh();
  };
  const newChat = async () => {
    setShowSessions(false);
    clearLiveTurnUi();
    await api.post('/api/chat/session', { action: 'new' });
    await refresh();
  };

  // Speaker lookup for per-message avatars/names. Memoized on the cast array
  // (which only changes identity when state refetches) so its stability
  // carries into the memoized TranscriptRows — a fresh Map every render was
  // enough to defeat that memo entirely. Hook, so it must sit above the
  // early returns.
  const castById = useMemo(
    () => new Map((state?.cast ?? []).map((c) => [c.id, c])),
    [state?.cast],
  );

  if (!state || opening || state.isLoadingSession) {
    if (loadError && !opening) {
      return (
        <div className="page centered-col">
          <p className="muted">⚠️ {loadError}</p>
          <button className="primary" onClick={() => void refresh()}>
            Try again
          </button>
        </div>
      );
    }
    return <div className="centered"><div className="spinner" /></div>;
  }

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
  // A lite scene guest has no realism of its own. Falling through to
  // `state.realism` here showed the HOST's bond/trust/needs under the
  // guest's name; desktop shows a 'Lite NPC' banner instead.
  const focusedMember = focusedId ? cast.find((c) => c.id === focusedId) : undefined;
  const focusedIsLiteGuest =
    !!focusedMember && !focusedMember.isHost && !focusedMember.realismEnabled;
  const realismForPanel = focusRealism ?? state.realism;
  const insight = realismForPanel ? (
    <ChatInsight
      realism={realismForPanel}
      focusedIsLiteGuest={focusedIsLiteGuest}
      lorebook={state.lorebook}
      loreTokens={state.loreTokens}
      loreBudget={state.loreBudget}
      loreOverflow={state.loreOverflow}
      draft={draft}
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
      toolSupport={state.toolSupport}
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
            <button
              className="link-btn"
              title="Who you are in this chat"
              onClick={() => setShowPersona(true)}
            >
              Persona
            </button>
            <button className="link-btn" onClick={() => setShowTheme(true)}>
              Theme
            </button>
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

        {importNotice && (
          <div className="chat-import-notice">
            <p>{importNotice}</p>
            <button
              type="button"
              className="link-btn"
              aria-label="Dismiss"
              onClick={() => setImportNotice('')}
            >
              ✕
            </button>
          </div>
        )}
        {sendError && (
          <div className="chat-import-notice" role="alert">
            <p>
              ⚠️ {sendError.message}
              <br />
              <span className="muted">Still here, not sent: “{sendError.text}”</span>
            </p>
            <button
              type="button"
              className="link-btn"
              disabled={sendError.retrying}
              onClick={() => void retrySend()}
            >
              {sendError.retrying ? 'Sending…' : 'Try again'}
            </button>
            <button
              type="button"
              className="link-btn"
              aria-label="Dismiss"
              onClick={() => setSendError(null)}
            >
              ✕
            </button>
          </div>
        )}
        {state.absencePhrase && state.sessionId && !absenceDismissed.has(state.sessionId) && (
          <div className="absence-banner">
            <span className="absence-banner-icon">🕰️</span>
            <div className="absence-banner-body">
              <div className="absence-banner-title">
                It's been {state.absencePhrase} — where we left off:
              </div>
              {state.summary?.trim() ? (
                <div className="absence-banner-recap">{state.summary.trim()}</div>
              ) : null}
            </div>
            <button
              className="absence-banner-close"
              aria-label="Dismiss"
              onClick={() =>
                setAbsenceDismissed((prev) => new Set(prev).add(state.sessionId!))
              }
            >
              ✕
            </button>
          </div>
        )}
        <ChatMessageList
          messages={state.messages}
          castById={castById}
          multiCast={multiCast}
          lastIndex={lastIndex}
          busy={state.isGenerating}
          streaming={streaming}
          genStatus={state.isGenerating ? genStatus : null}
          scrollRef={scrollRef}
          canSpeak={!!voice?.ttsEnabled}
          onBeginEdit={beginEdit}
          onSwipe={swipe}
          onRegenerate={regenerate}
          onContinue={continueGen}
          onFork={fork}
          onDelete={del}
          onReprocess={setReprocessIndex}
          onRevert={revertNeeds}
          greetCount={state.totalGreetings}
          greetingIndex={state.greetingIndex}
          onVariantPicked={() => void refresh()}
        />

        {editTarget && (
          <MessageEditModal
            initialText={editTarget.text}
            onCancel={() => setEditTarget(null)}
            onSave={saveEdit}
          />
        )}

        <ProcessingOverlay p={processing} onCancel={cancelRealism} />

        {imageProg && (
          <div className="image-progress-card">
            {imageProg.preview && (
              <img className="image-progress-preview" src={imageProg.preview} alt="generating" />
            )}
            <div className="image-progress-bar">
              <div
                className={`image-progress-fill${imageProg.progress == null ? ' indeterminate' : ''}`}
                style={imageProg.progress != null ? { width: `${Math.round(imageProg.progress * 100)}%` } : undefined}
              />
            </div>
            <span className="muted small">
              {imageProg.progress != null
                ? `Painting… ${Math.round(imageProg.progress * 100)}%`
                : 'Painting…'}
            </span>
          </div>
        )}

        <ChatComposer
          onSend={sendMessage}
          onStop={stop}
          isGenerating={state.isGenerating}
          isSettlingTurn={!!state.isSettlingTurn}
          isSendWaitingOnSettle={!!state.isSendWaitingOnSettle}
          canMic={canMic}
          onDraftChange={setDraft}
          cast={cast}
          impersonateFill={impersonateFill}
          onImpersonate={(prefix) => {
            void api.post('/api/chat/impersonate', { prefix });
          }}
          apiReady={state.llmReady !== false}
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

      {/* Persistent insight column — desktop only. The 1024px here is the same
          line `.chat-aside`'s media query draws; below it the column is
          display:none, and a hidden mount still ran every sidebar fetch. */}
      {isDesktop && insight && (
        <aside className="chat-aside" style={{ width: asideWidth }}>
          <div className="aside-resizer" onMouseDown={startAsideResize} title="Drag to resize" />
          {insight}
        </aside>
      )}

      {/* Insight as a slide-over drawer below desktop. Also gated, so widening
          the window past 1024 with the drawer still open can't mount it twice. */}
      {!isDesktop && showStats && insight && (
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

      {showPersona && (
        <ChatPersonaModal onClose={() => setShowPersona(false)} onChanged={refresh} />
      )}

      {reprocessIndex !== null && (
        <ReprocessNeedsModal
          onSubmit={submitReprocess}
          onClose={() => setReprocessIndex(null)}
        />
      )}

      {chance && (
        <ChanceTimeModal
          event={chance.event}
          revealed={chance.revealed}
          onReveal={revealFate}
          onAccept={acceptFate}
        />
      )}

      {state.imagePromptReview && (
        <ImagePromptReviewModal
          prompt={state.imagePromptReview}
          onGenerate={(edited) =>
            void api.post('/api/chat/image-review', { prompt: edited }).catch(() => {})
          }
          onCancel={() => void api.post('/api/chat/image-review', {}).catch(() => {})}
        />
      )}

      {showSessions && (
        <ConversationsDrawer
          sessions={sessions}
          loading={loadingSessions}
          activeSessionId={state.sessionId}
          onLoad={loadSession}
          onNew={newChat}
          onDelete={async (id) => {
            await api.post('/api/chat/session', {
              action: 'delete',
              sessionId: id,
              startReplacement: id === state.sessionId,
            });
            await openSessions();
            await refresh();
          }}
          onClose={() => setShowSessions(false)}
          exportTitle={title}
          canExport={state.messages.length > 0}
          canImport={!state.isGenerating && !state.isSettlingTurn}
          onImported={(message) => {
            setShowSessions(false);
            setImportNotice(message);
            void refresh();
          }}
        />
      )}

      {showTheme && (
        <div className="drawer-backdrop" onClick={() => setShowTheme(false)}>
          <div className="settings-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="drawer-head">
              <span>Chat theme</span>
              <button className="link-btn" onClick={() => setShowTheme(false)}>Close</button>
            </div>
            <ChatThemeSettings
              overrides={state.themeOverrides ?? null}
              onSave={saveTheme}
            />
          </div>
        </div>
      )}
    </div>
  );
}
