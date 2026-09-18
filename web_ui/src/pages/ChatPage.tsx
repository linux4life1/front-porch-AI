// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useMemo, useState, type MouseEvent as ReactMouseEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/client';
import { CastBar } from '../components/CastBar';
import { SmartImg } from '../components/ChatAvatar';
import { ChatMessageList } from '../components/ChatMessageList';
import { ChatComposer } from '../components/ChatComposer';
import { ChatInsight } from '../components/ChatInsight';
import { ConversationsDrawer } from '../components/ConversationsDrawer';
import { ChatThemeSettings } from '../components/ChatThemeSettings';
import { ProcessingOverlay } from '../components/ProcessingOverlay';
import { type Realism } from '../components/chatTypes';
import { useLayout } from '../hooks/useBreakpoint';
import { ChatOverlays } from './chat/ChatOverlays';
import { useChatSend } from './chat/useChatSend';
import { useChatSession } from './chat/useChatSession';

export function ChatPage() {
  const navigate = useNavigate();
  // The insight column is desktop-only (CSS hides it below 1024px) and the
  // Stats drawer is its phone/tablet stand-in — mount whichever one is on
  // screen. `display:none` does not unmount, so rendering both meant every
  // chat refresh fired the sidebar's GETs (tools / journal / growth / places)
  // for a panel nobody could see, twice over with the drawer open.
  const { isDesktop } = useLayout();
  const session = useChatSession();
  const send = useChatSend(session.refresh);
  const {
    opening, state, loadError, streaming, chance, imageProg, genStatus,
    processing, showSessions, setShowSessions, sessions, loadingSessions,
    toolsBump, voice, impersonateFill, scrollRef, refresh, stop, revealFate,
    acceptFate, cancelRealism, openSessions, loadSession, newChat,
  } = session;
  const {
    sendError, setSendError, editTarget, setEditTarget, reprocessIndex,
    setReprocessIndex, sendMessage, retrySend, regenerate, continueGen, fork,
    swipe, del, beginEdit, saveEdit, saveAuthorNote, saveTheme,
    submitReprocess, revertNeeds,
  } = send;

  // Living Time §2: sessions whose welcome-back banner was dismissed (ephemeral).
  const [absenceDismissed, setAbsenceDismissed] = useState<Set<string>>(new Set());
  // Composer draft mirror — powers the lorebook "would trigger next" preview.
  const [draft, setDraft] = useState('');
  // Resizable insight sidebar (desktop) — width persists across sessions.
  const [asideWidth, setAsideWidth] = useState<number>(() => {
    const v = typeof localStorage !== 'undefined' ? localStorage.getItem('fpai.asideWidth') : null;
    const n = v ? parseInt(v, 10) : NaN;
    return Number.isFinite(n) ? Math.min(560, Math.max(260, n)) : 320;
  });
  const [importNotice, setImportNotice] = useState('');
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
        onPick={(name, full) => {
          void sendMessage(`/join ${full ? '--full ' : ''}${name}`);
        }}
        onClosePicker={() => setShowPicker(false)}
        editTarget={editTarget}
        onCancelEdit={() => setEditTarget(null)}
        onSaveEdit={saveEdit}
        showPersona={showPersona}
        onClosePersona={() => setShowPersona(false)}
        onPersonaChanged={refresh}
        reprocessIndex={reprocessIndex}
        onSubmitReprocess={submitReprocess}
        onCloseReprocess={() => setReprocessIndex(null)}
        chance={chance}
        onReveal={revealFate}
        onAccept={acceptFate}
        imagePromptReview={state.imagePromptReview}
      />
    </div>
  );
}
