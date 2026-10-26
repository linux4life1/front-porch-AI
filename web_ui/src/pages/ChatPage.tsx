// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useMemo, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { CastBar } from '../components/CastBar';
import { DirectorStrip, ExitUndoBar } from '../components/DirectorStrip';
import { ChatMessageList } from '../components/ChatMessageList';
import { ChatComposer } from '../components/ChatComposer';
import { ChatInsight } from '../components/ChatInsight';
import { ConversationsDrawer } from '../components/ConversationsDrawer';
import { ChatThemeSettings } from '../components/ChatThemeSettings';
import { PromptSourcePickerModal, PromptSourceSettings } from '../components/PromptSource';
import { ProcessingOverlay } from '../components/ProcessingOverlay';
import { useEvaluationView } from '../components/useEvaluationView';
import { type Realism } from '../components/chatTypes';
import { useLayout } from '../hooks/useBreakpoint';
import { ChatHeader } from './chat/ChatHeader';
import { ChatNotices } from './chat/ChatNotices';
import { ChatOverlays } from './chat/ChatOverlays';
import { SceneEffectsCanvas } from './chat/SceneEffectsCanvas';
import { useChatFind } from './chat/useChatFind';
import { useChatSend } from './chat/useChatSend';
import { useChatSession } from './chat/useChatSession';
import { FindBar } from '../components/FindBar';
import { FindSurfaceContext } from '../components/chatSearch';
import { useFollowStreamingReplies } from '../followStreaming';
import { useUserMessageSide } from '../userMessageSide';

export function ChatPage() {
  const navigate = useNavigate();
  // The insight column is desktop-only (CSS hides it below 1024px) and the
  // Stats drawer is its phone/tablet stand-in — mount whichever one is on
  // screen. `display:none` does not unmount, so rendering both meant every
  // chat refresh fired the sidebar's GETs (tools / journal / growth / places)
  // for a panel nobody could see, twice over with the drawer open.
  const { isDesktop, isPhone } = useLayout();
  const followStreamingReplies = useFollowStreamingReplies();
  const evaluationView = useEvaluationView();
  useUserMessageSide();
  const session = useChatSession();
  const send = useChatSend(session.refresh);
  const {
    opening, switching, state, loadError, streaming, chance, imageProg, genStatus,
    processing, showSessions, setShowSessions, sessions, loadingSessions,
    toolsBump, voice, impersonateFill, scrollRef, onTranscriptScroll, refresh, stop, revealFate,
    acceptFate, cancelRealism, dismissStoppedReply, skipObjectiveCheck, openSessions, loadSession, newChat,
  } = session;
  const {
    sendError, setSendError, actionError, setActionError, reportActionFailure,
    editTarget, setEditTarget, reprocessIndex, setReprocessIndex, sendMessage, retrySend, regenerate, continueGen, fork,
    swipe, del, pendingConfirm, confirmPending, cancelPending, beginEdit, saveEdit, saveAuthorNote, saveTheme,
    submitReprocess, submitReprocessFeelings, revertNeeds,
  } = send;

  // Living Time §2: sessions whose welcome-back banner was dismissed (ephemeral).
  const [absenceDismissed, setAbsenceDismissed] = useState<Set<string>>(new Set());
  // ⌘F find-in-chat: server-scan counts + leaf highlight surface (parity
  // with the desktop ChatFindController).
  const lastTranscriptMsg = state?.messages?.[state.messages.length - 1];
  // Messages whose speaker label (multi-cast only) shows exactly the name
  // the engine scanned; sender hits anywhere else have nothing to light.
  const senderLabelShown = useMemo(() => {
    const cast = state?.cast ?? [];
    const shown = new Set<number>();
    if (cast.length < 2) return shown;
    const names = new Map(cast.map((c) => [c.id, c.name]));
    for (const m of state?.messages ?? []) {
      if (!m.isUser && m.characterId && names.get(m.characterId) === m.sender) shown.add(m.index);
    }
    return shown;
  }, [state?.cast, state?.messages]);
  const find = useChatFind({
    sessionId: state?.sessionId,
    senderLabelShown,
    transcriptVersion: `${state?.messages?.length ?? 0}|${lastTranscriptMsg?.text?.length ?? 0}`,
  });
  // Composer draft mirror — powers the lorebook "would trigger next" preview.
  const [draft, setDraft] = useState('');
  // Resizable insight sidebar (desktop) — width persists across sessions.
  const [asideWidth, setAsideWidth] = useState<number>(() => {
    const v = typeof localStorage !== 'undefined' ? localStorage.getItem('fpai.asideWidth') : null;
    const n = v ? parseInt(v, 10) : NaN;
    return Number.isFinite(n) ? Math.min(560, Math.max(260, n)) : 320;
  });
  const [importNotice, setImportNotice] = useState('');
  // Slice 7: the mint proposal answered-but-unseen after a failed
  // request (see onAnswerPlaceMint). Cleared when the flag empties.
  const [dismissedMint, setDismissedMint] = useState('');
  // Reset the local answer-memory once the server flag actually clears,
  // so the NEXT proposal of any name is heard again (review #607).
  const mintKey = (m: { name: string; descriptor: string }) =>
    `${m.name}\u0000${m.descriptor}`;
  useEffect(() => {
    if (!state?.pendingMint && dismissedMint) setDismissedMint('');
  }, [state?.pendingMint, dismissedMint]);
  const [showStats, setShowStats] = useState(false);
  const [showTheme, setShowTheme] = useState(false);
  const [showPersona, setShowPersona] = useState(false);
  const [showPicker, setShowPicker] = useState(false);
  // Unified-cast UI: which participant the sidebar is scoped to, the add-picker,
  // and the focused participant's realism (null = use the default host snapshot).
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [focusRealism, setFocusRealism] = useState<Realism | null>(null);

  const canMic = !!voice?.sttAvailable && typeof window !== 'undefined' && window.isSecureContext;

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

  // `/join --full` (and ambiguous `/join`) parks a picker on the Dart side.
  useEffect(() => {
    if (state?.pendingPicker != null) setShowPicker(true);
  }, [state?.pendingPicker]);

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
  }, [editTarget, showStats, showSessions, setShowSessions]);

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

  // Speaker lookup for per-message avatars/names. Memoized on the cast array
  // (which only changes identity when state refetches) so its stability
  // carries into the memoized TranscriptRows — a fresh Map every render was
  // enough to defeat that memo entirely. Hook, so it must sit above the
  // early returns.
  const castById = useMemo(
    () => new Map((state?.cast ?? []).map((c) => [c.id, c])),
    [state?.cast],
  );

  if (!state || opening || switching || state.isLoadingSession) {
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
  // One Director setting to the app, then a refresh (or the failure shown).
  const postDirector = (path: string, body: object, what: string) => {
    api
      .post(`/api/chat/director/${path}`, body)
      .then(() => refresh())
      .catch((e) => reportActionFailure(what, e));
  };
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
  const focusedIsLiteGuest = !!focusedMember?.isLite;
  const realismForPanel = focusRealism ?? state.realism;
  const insight = realismForPanel ? (
    <ChatInsight
      realism={realismForPanel}
      focusedIsLiteGuest={focusedIsLiteGuest}
      lorebook={state.lorebook}
      groupLorebookUnreadable={state.groupLorebookUnreadable}
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
      focusedPlaceholderPortrait={focused?.placeholderPortrait}
      toolsKey={toolsBump}
      focusedId={focusedId}
      groupId={state.groupId ?? null}
      onCommand={sendMessage}
      cast={cast}
      onFocus={focusParticipant}
      toolSupport={state.toolSupport}
    />
  ) : null;

  // Slice 7: hide a mint the author already answered locally until the
  // server flag actually clears or a DIFFERENT name arrives (a failed
  // POST must not reopen the modal on every poll — review #607).
  const visibleMint =
    state.pendingMint && mintKey(state.pendingMint) !== dismissedMint
      ? state.pendingMint
      : null;

  return (
    <div className="chat-layout">
      <div className="chat-view">
        {/* The Ambient Stage's moving weather, behind every other child. */}
        <SceneEffectsCanvas scene={state.scene} generating={!!state.isGenerating || !!state.isSettlingTurn || streaming !== ''} />
        <ChatHeader
          title={title}
          focused={focused}
          isGroupMode={state.isGroupMode ?? false}
          expressionLabel={state.expressionLabel}
          characterId={state.character?.id}
          isPhone={isPhone}
          hasStats={!!insight}
          onEdit={editId ? () => navigate(`/edit/${editId}`) : undefined}
          onStats={() => setShowStats(true)}
          onPersona={() => setShowPersona(true)}
          onTheme={() => setShowTheme(true)}
          onConversations={openSessions}
        />

        <CastBar
          cast={cast}
          focusedId={focusedId}
          busy={state.isGenerating}
          settling={!!state.isSettlingTurn}
          guestStatus={state.guestActivity?.status ?? null}
          guestIsError={state.guestActivity?.isError ?? false}
          pendingDetection={state.pendingDetection ?? null}
          onFocus={focusParticipant}
          onAdd={() => setShowPicker(true)}
          onCommand={sendMessage}
          onSetAway={(id, away) => {
            api
              .post('/api/chat/cast/away', { id, away })
              .then(() => refresh())
              .catch((e) => reportActionFailure(away ? 'mark them away' : 'bring them back', e));
          }}
          canRemoveMember={state.director?.canRemoveMember ?? true}
        />
        {state.director && (state.isGroupMode || cast.length > 1) && (
          <DirectorStrip
            director={state.director}
            busy={state.isGenerating}
            onCommand={sendMessage}
            memberNames={cast.map((c) => c.name)}
            onAutoPlay={(on) => postDirector('autoplay', { on }, 'change auto-chat')}
            onPauseAutoPlay={() =>
              postDirector('autoplay', { on: false, pause: true }, 'pause auto-chat')
            }
            onDelay={(seconds) => postDirector('delay', { seconds }, 'change the auto-chat delay')}
            onGoal={(text) => postDirector('goal', { text }, 'change the scene goal')}
            onClearWhisper={(id) => postDirector('whisper', { id, text: '' }, 'clear the whisper')}
            onTurnBudget={(turns) => postDirector('budget', { turns }, 'change the auto-chat run')}
          />
        )}
        <ExitUndoBar
          undo={state.exitUndo ?? null}
          onUndo={() => {
            api
              .post('/api/chat/exit-undo')
              .then(() => refresh())
              .catch((e) => reportActionFailure('undo that exit', e));
          }}
        />

        <ChatNotices
          importNotice={importNotice}
          onDismissImport={() => setImportNotice('')}
          sendError={sendError}
          onRetrySend={() => void retrySend()}
          onDismissSendError={() => setSendError(null)}
          actionError={actionError}
          onDismissActionError={() => setActionError(null)}
          stoppedReply={state.stoppedReply ?? null}
          onRetryStopped={() => void regenerate()}
          onDismissStopped={() => void dismissStoppedReply()}
        />
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
        <div className="chat-find-host">
          <FindSurfaceContext.Provider value={find.surface}>
            <ChatMessageList
              sessionId={state.sessionId}
              messages={state.messages}
              castById={castById}
              multiCast={multiCast}
              lastIndex={lastIndex}
              busy={state.isGenerating}
              settling={!!state.isSettlingTurn}
              streaming={streaming}
              followStreamingReplies={followStreamingReplies}
              genStatus={state.isGenerating ? genStatus : null}
              scrollRef={scrollRef}
              onScroll={onTranscriptScroll}
              canSpeak={!!voice?.ttsEnabled}
              onBeginEdit={beginEdit}
              onSwipe={swipe}
              onRegenerate={regenerate}
              lookupWeb={!!state.lookupSources?.web}
              lookupWiki={!!state.lookupSources?.wiki}
              onContinue={continueGen}
              onFork={fork}
              onDelete={del}
              onReprocess={setReprocessIndex}
              onRevert={revertNeeds}
              greetCount={state.totalGreetings}
              greetingIndex={state.greetingIndex}
              onVariantPicked={refresh}
              onActionFailed={reportActionFailure}
              revealTarget={find.reveal}
            />
          </FindSurfaceContext.Provider>
          {find.open && (
            <FindBar
              value={find.query}
              onValue={find.setQuery}
              regexOn={find.regexOn}
              onToggleRegex={find.toggleRegex}
              caseOn={find.caseOn}
              onToggleCase={find.toggleCase}
              waiting={find.waiting}
              bad={find.bad}
              slow={find.slow}
              counter={find.counter}
              wildcardChip={find.wildcardChip}
              onStep={find.step}
              onClose={find.close}
            />
          )}
        </div>

        {evaluationView.error && <p role="alert">{evaluationView.error}</p>}
        <ProcessingOverlay minimized={evaluationView.minimized} onMinimizedChange={evaluationView.change} saving={evaluationView.saving} p={processing} onCancel={cancelRealism} onSkipObjective={skipObjectiveCheck} />

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
          isGenerating={session.replying}
          isSettlingTurn={!!state.isSettlingTurn}
          isSendWaitingOnSettle={!!state.isSendWaitingOnSettle}
          canMic={canMic}
          onDraftChange={setDraft}
          cast={cast}
          impersonateFill={impersonateFill}
          onImpersonate={(prefix) => {
            api
              .post('/api/chat/impersonate', { prefix })
              .catch((e) => reportActionFailure('write your line for you', e));
          }}
          apiReady={state.llmReady !== false}
          apiHint={state.llmHint}
          directing={!!state.director?.directing}
        />
      </div>

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

      {showSessions && (
        <ConversationsDrawer
          sessions={sessions}
          loading={loadingSessions}
          activeSessionId={state.sessionId}
          onLoad={(id) =>
            loadSession(id).catch((e) => reportActionFailure('open that conversation', e))
          }
          onNew={() =>
            newChat().catch((e) => reportActionFailure('start a new chat', e))
          }
          onDelete={async (id) => {
            try {
              await api.post('/api/chat/session', {
                action: 'delete',
                sessionId: id,
                startReplacement: id === state.sessionId,
              });
            } catch (e) {
              setShowSessions(false);
              reportActionFailure('delete that conversation', e);
              return;
            }
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
              <span>Chat settings</span>
              <button className="link-btn" onClick={() => setShowTheme(false)}>Close</button>
            </div>
            {state.promptSource && (
              <PromptSourceSettings
                state={state.promptSource}
                onDone={refresh}
                onFailed={reportActionFailure}
              />
            )}
            <ChatThemeSettings
              overrides={state.themeOverrides ?? null}
              onSave={async (overrides) => {
                setShowTheme(false);
                await saveTheme(overrides);
              }}
            />
          </div>
        </div>
      )}

      <ChatOverlays
        showPicker={showPicker}
        pickerFull={state?.pendingPicker?.full ?? false}
        pickerFilter={state?.pendingPicker?.filter ?? ''}
        onPick={(name, full) => {
          void sendMessage(`/join ${full ? '--full ' : ''}${name}`);
        }}
        onClosePicker={() => {
          setShowPicker(false);
          void api.post('/api/chat/guest-picker/dismiss', {}).catch(() => {});
        }}
        editTarget={editTarget}
        onCancelEdit={() => setEditTarget(null)}
        onSaveEdit={saveEdit}
        showPersona={showPersona}
        onClosePersona={() => setShowPersona(false)}
        onPersonaChanged={refresh}
        reprocessIndex={reprocessIndex}
        messages={state.messages}
        onSubmitReprocess={submitReprocess}
        onSubmitReprocessFeelings={submitReprocessFeelings}
        onCloseReprocess={() => setReprocessIndex(null)}
        chance={chance}
        onReveal={revealFate}
        onAccept={acceptFate}
        placeMint={visibleMint}
        onAnswerPlaceMint={async (action) => {
          // One attempt, one answer: the modal closes on the tap. If the
          // request then fails (network), the server flag is still set —
          // re-showing it every poll is the nag loop review #607 caught.
          // The next DIFFERENT proposal, or a chat reopen, speaks again.
          if (state.pendingMint) setDismissedMint(mintKey(state.pendingMint));
          try {
            const res = await api.post<{ ok?: boolean; error?: string }>(
              '/api/chat/place-mint',
              { action },
            );
            if (!res.ok && res.error) setImportNotice(res.error);
          } catch (e) {
            setImportNotice(e instanceof Error ? e.message : String(e));
          }
        }}
        placeMove={state.pendingPlaceMove ?? null}
        onAnswerPlaceMove={(accept) =>
          void api.post('/api/chat/place-move', { accept }).catch(() => {})
        }
        imagePromptReview={state.imagePromptReview}
        pendingConfirm={pendingConfirm}
        onConfirmPending={confirmPending}
        onCancelPending={cancelPending}
      />
      {state.promptSource?.picker && (
        <PromptSourcePickerModal
          picker={state.promptSource.picker}
          onDone={refresh}
          onFailed={reportActionFailure}
        />
      )}
    </div>
  );
}
