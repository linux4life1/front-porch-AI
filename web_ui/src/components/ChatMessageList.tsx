// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scrolling chat transcript: per-message bubbles (with speaker labels in a
// multi-character scene, collapsible thinking blocks, Realism/Needs chips, and
// the per-message action toolbar) plus the live streaming bubble. Message edit
// is a fullscreen modal owned by ChatPage (MessageEditModal).

import { memo, type RefObject } from 'react';
import { MessageContent } from './MessageContent';
import { ChipsRow } from './ChipsRow';
import { MessageActions } from './MessageActions';
import { type CastMember } from './CastBar';
import { type Message } from './chatTypes';
import { canonicalizeReasoning } from '../utils/reasoningMarkers';

/// Truthful generation status (desktop status-bar parity): live prompt-reading
/// counts from the managed local backend + which background pass holds the
/// single local slot. Null fields = no live data (remote backend). The server
/// interpolates estFraction between the backend's per-batch console lines and
/// flags promptDone only when the console confirmed completion.
export type GenStatus = {
  phase: string;
  busyWith: string | null;
  queued: number;
  promptCur: number | null;
  promptTotal: number | null;
  promptDone: boolean;
  estFraction: number | null;
  genCur: number | null;
  genTotal: number | null;
};

/// Exact count with thousands separators ("8,347") — a live ticker, not just
/// a percent (maintainer request).
function fmtExact(n: number): string {
  return n.toLocaleString('en-US');
}

/// Mirror of the desktop status-bar wording so both surfaces tell the same
/// truth about the wait.
function genStatusLabel(s: GenStatus): { label: string; fraction: number | null } {
  // Backend queue depth is a neutral fact — never attributed (may be
  // someone waiting on us).
  const queueNote =
    s.queued > 0 ? ` — ${s.queued} request${s.queued === 1 ? '' : 's'} queued` : '';
  const hasLive = s.promptTotal != null && s.promptTotal > 0;
  const fraction = hasLive
    ? (s.estFraction ?? Math.min(1, (s.promptCur ?? 0) / (s.promptTotal as number)))
    : null;
  const estTokens = hasLive
    ? (s.promptDone
        ? (s.promptTotal as number)
        : Math.round((s.promptTotal as number) * (fraction ?? 0)))
    : 0;
  const counts = hasLive
    ? `${fmtExact(estTokens)} / ${fmtExact(s.promptTotal as number)} tokens`
    : '';
  if (s.busyWith) {
    const pass = s.busyWith === 'journal' ? 'journal pass' : 'growth pass';
    if (hasLive) {
      const stage =
        (s.genTotal ?? 0) > 0
          ? `writing (${s.genCur} tokens)`
          : s.promptDone
            ? 'finishing up'
            : `reading ${counts} (${Math.round((fraction ?? 0) * 100)}%)`;
      return { label: `Waiting — ${pass} is using the model: ${stage}`, fraction };
    }
    return { label: `Waiting — ${pass} is using the model…`, fraction: null };
  }
  if (hasLive && !s.promptDone) {
    return {
      label: `Reading prompt — ${counts} (${Math.round((fraction ?? 0) * 100)}%)${queueNote}`,
      fraction,
    };
  }
  if (hasLive) {
    // Prompt fully read. A running decode with no streamed token yet IS our
    // reply warming up — only busyWith marks someone else's work.
    return {
      label:
        (s.genTotal ?? 0) > 0
          ? `Starting the reply — ${s.genCur} tokens written${queueNote}`
          : `Prompt read — starting the reply…${queueNote}`,
      fraction: 1,
    };
  }
  if (s.phase === 'thinking') return { label: 'Model is thinking…', fraction: null };
  return { label: 'Processing prompt…', fraction: null };
}

type TranscriptProps = {
  messages: Message[];
  castById: Map<string, CastMember>;
  multiCast: boolean;
  lastIndex: number;
  busy: boolean;
  canSpeak: boolean;
  onBeginEdit: (m: Message) => void;
  onSwipe: (index: number, direction: number) => void;
  onRegenerate: () => void;
  onContinue: () => void;
  onFork: (index: number) => void;
  onDelete: (index: number) => void;
  onReprocess: (index: number) => void;
  onRevert: (index: number) => void;
  greetCount?: number;
  greetingIndex?: number;
  onVariantPicked?: () => void;
};

// Memoized separately from the live streaming tail: token/processing WS
// frames re-render ChatPage many times a second during a turn, and
// reconciling every transcript row each frame is what froze iPad Safari on
// long chats. The handlers are useCallback-stable in ChatPage, so these
// props only change identity when the transcript genuinely changes.
const TranscriptRows = memo(function TranscriptRows({
  messages,
  castById,
  multiCast,
  lastIndex,
  busy,
  canSpeak,
  onBeginEdit,
  onSwipe,
  onRegenerate,
  onContinue,
  onFork,
  onDelete,
  onReprocess,
  onRevert,
  greetCount,
  greetingIndex,
  onVariantPicked,
}: TranscriptProps) {
  const userHasReplied = messages.some((m) => m.isUser);
  return (
    <>
      {messages.map((m) => {
        const speaker = !m.isUser && m.characterId ? castById.get(m.characterId) : undefined;
        // Living Time §1: dreams render as a centered narration banner
        // (desktop parity — same treatment as Chance Time).
        if (m.isDream) {
          return (
            <div key={m.index} className="msg-row">
              <div className="dream-banner">
                🌙 <em>{m.sender} dreamt: {m.text}</em>
              </div>
            </div>
          );
        }
        return (
          <div key={m.index} className="msg-row">
            {multiCast && speaker && <span className="msg-speaker">{speaker.name}</span>}
            {m.hasThinking && m.thinkingContent && (
              <details className="thinking">
                <summary>💭 Thoughts</summary>
                <div className="thinking-body">{m.thinkingContent}</div>
              </details>
            )}
            <div className={m.isUser ? 'bubble user' : 'bubble ai'}>
              {m.image && (
                // Generated image (from /image or the Image Studio) —
                // native right-click gives "Save image as…" in a browser.
                <img
                  className="chat-image"
                  src={`/api/image/saved/${encodeURIComponent(m.image)}`}
                  alt={m.imagePrompt || 'generated image'}
                  title={m.imagePrompt}
                  loading="lazy"
                />
              )}
              {m.text ? (
                <MessageContent text={m.text} />
              ) : !m.isUser && m.thinkingContent && !busy ? (
                // Thought-only reply (the model spent its whole turn inside a
                // <think> block): say so instead of a bare empty bubble.
                <span className="muted small">
                  💭 Only thoughts this turn — Continue or Regenerate for a
                  spoken reply.
                </span>
              ) : null}
            </div>
            {!m.isUser && m.chips && (
              <ChipsRow
                chips={m.chips}
                isLast={m.index === lastIndex}
                busy={busy}
                onReprocess={() => onReprocess(m.index)}
                onRevert={() => onRevert(m.index)}
              />
            )}
            <MessageActions
              m={m}
              isLast={m.index === lastIndex}
              busy={busy}
              canSpeak={canSpeak}
              greetCount={greetCount}
              greetingIndex={greetingIndex}
              userHasReplied={userHasReplied}
              onSwipe={onSwipe}
              onRegenerate={onRegenerate}
              onContinue={onContinue}
              onFork={() => onFork(m.index)}
              onEdit={() => onBeginEdit(m)}
              onDelete={() => onDelete(m.index)}
              onVariantPicked={onVariantPicked}
            />
          </div>
        );
      })}
    </>
  );
});

export function ChatMessageList({
  streaming,
  genStatus,
  scrollRef,
  onScroll,
  ...transcript
}: TranscriptProps & {
  streaming: string;
  genStatus: GenStatus | null;
  scrollRef: RefObject<HTMLDivElement>;
  onScroll?: () => void;
}) {
  return (
    <div className="chat-messages" ref={scrollRef} onScroll={onScroll}>
      <TranscriptRows {...transcript} />
      {streaming && (() => {
        // Separate a (possibly still-open) <think> block so reasoning streams
        // into a muted "thinking…" area and the reply shows below — mirrors how
        // the finished message renders its collapsible thinking block.
        // Case-INSENSITIVE like the Dart strip (<THINK> is valid there too);
        // the old case-sensitive match streamed an uppercase think block as
        // normal reply text that then vanished into an empty bubble at done.
        const canonical = canonicalizeReasoning(streaming)
        const lower = canonical.toLowerCase();
        const open = lower.indexOf('<think>');
        let thinking = '';
        let rest = canonical;
        if (open !== -1) {
          const after = canonical.slice(open + 7);
          const close = after.toLowerCase().indexOf('</think>');
          thinking = close === -1 ? after : after.slice(0, close);
          rest = canonical.slice(0, open) + (close === -1 ? '' : after.slice(close + 8));
        }
        return (
          <div className="bubble ai streaming" aria-live="polite">
            {thinking.trim() && (
              <details className="thinking">
                <summary>💭 thinking…</summary>
                <div className="thinking-body">{thinking}</div>
              </details>
            )}
            {rest && <MessageContent text={rest} />}
          </div>
        );
      })()}
      {!streaming && genStatus && (() => {
        // Before the first token arrives, name the wait truthfully instead of
        // showing nothing: real prompt-reading progress from the local
        // backend, or which background pass is holding the slot.
        const { label, fraction } = genStatusLabel(genStatus);
        return (
          <div className="bubble ai streaming gen-status" aria-live="polite">
            <span className="muted small">{label}</span>
            {fraction != null && (
              <div className="gen-status-track">
                <div
                  className="gen-status-fill"
                  style={{ width: `${Math.round(fraction * 100)}%` }}
                />
              </div>
            )}
          </div>
        );
      })()}
    </div>
  );
}
