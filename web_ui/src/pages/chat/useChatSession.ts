// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Load / socket / history for the chat page. The page owns layout; this hook
// owns the GET /api/chat/state refresh, the multiplexed WS, and session switch.

import { useCallback, useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { NO_PROCESSING, type Processing } from '../../components/ProcessingOverlay';
import { resolveThemeColors } from '../../components/ChatThemeSettings';
import { type GenStatus } from '../../components/ChatMessageList';
import { type SessionSummary } from '../../components/ConversationsDrawer';
import { useAuth } from '../../auth/AuthContext';
import { describeChatLoadFailure } from '../chatLoad';
import { type ChatState } from './chatState';

export function useChatSession() {
  const [searchParams] = useSearchParams();
  const opening = searchParams.get('opening') === '1';
  const { setAuthenticated } = useAuth();
  const [state, setState] = useState<ChatState | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const tokenSessionRef = useRef<string | null>(null);
  // Why the chat could not be loaded — shown instead of a spinner that would
  // otherwise never resolve.
  const [loadError, setLoadError] = useState('');
  const [streaming, setStreaming] = useState('');
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
  const [showSessions, setShowSessions] = useState(false);
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(false);
  // Bumps whenever chat state refreshes (incl. WS chat_updated) so the tools
  // sidebar refetches its own snapshot in lock-step.
  const [toolsBump, setToolsBump] = useState(0);
  // Voice capability snapshot (TTS on? STT usable?) — gates the Speak/Mic UI.
  const [voice, setVoice] = useState<{ ttsEnabled: boolean; sttAvailable: boolean } | null>(null);
  // Live Impersonate composer fill (dedicated WS event — not the AI bubble).
  const [impersonateFill, setImpersonateFill] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  // Coalesces bursts of `chat_updated` (a single turn fires several: send, guest
  // actions, realism chip-attach, …) into one refresh so the transcript doesn't
  // reload repeatedly while the engines work.
  const refreshTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

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

  return {
    opening,
    state,
    loadError,
    streaming,
    chance,
    imageProg,
    genStatus,
    processing,
    showSessions,
    setShowSessions,
    sessions,
    loadingSessions,
    toolsBump,
    voice,
    impersonateFill,
    scrollRef,
    refresh,
    stop,
    revealFate,
    acceptFate,
    cancelRealism,
    openSessions,
    loadSession,
    newChat,
  };
}
