// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The chat input composer: the slash-command cheat sheet, the message textarea,
// the mic (STT) button, and the Send/Stop button. Extracted from ChatPage to
// keep that page under the file-size cap. Owns its own draft + slash-dismiss UI
// state; sending is delegated to onSend so all chat/network state stays in
// ChatPage.

import { useState, useRef, useEffect } from 'react';
import { MicButton } from './VoiceControls';
import { renderRpInline } from './rpText';

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

/** The in-progress "@" token ending at `caret`, or null. Mirrors the engine's
 *  boundary rule: the @ must not follow a word char/dot/hyphen/plus, so typing
 *  an email never opens the popup. */
function activeMentionQuery(
  text: string,
  caret: number,
): { start: number; prefix: string } | null {
  const head = text.slice(0, Math.max(0, Math.min(caret, text.length)));
  // Unicode letters/digits so accented names filter too — kept in lock-step
  // with the desktop MentionAutocomplete twin.
  const m = /(?:^|[^\w.+-])@([\p{L}\p{N}_]*)$/u.exec(head);
  if (!m) return null;
  const prefix = m[1];
  return { start: head.length - prefix.length - 1, prefix };
}

/** Case-insensitive candidate filter: full name or any name token starts with
 *  the typed prefix ("@van" finds "Mara Vance"). */
function mentionNameMatches(name: string, prefix: string): boolean {
  if (!prefix) return true;
  const p = prefix.toLowerCase();
  const n = name.trim().toLowerCase();
  return n.startsWith(p) || n.split(/\s+/).some((t) => t.startsWith(p));
}

export function ChatComposer({
  onSend,
  onStop,
  isGenerating,
  canMic,
  onDraftChange,
  cast,
}: {
  onSend: (text: string) => void;
  onStop: () => void;
  isGenerating: boolean;
  canMic: boolean;
  /** Live draft mirror for the lorebook "would trigger next" preview. */
  onDraftChange?: (text: string) => void;
  /** Present cast for the "@" autocomplete (host + guests, or group members).
   *  Omit / a lone host disables the popup. */
  cast?: { name: string; isHost: boolean; isLite: boolean }[];
}) {
  const [draft, setDraftState] = useState('');
  const setDraft = (v: string | ((d: string) => string)) => {
    setDraftState((prev) => {
      const next = typeof v === 'function' ? v(prev) : v;
      onDraftChange?.(next);
      return next;
    });
  };
  const [slashDismissed, setSlashDismissed] = useState(false);

  // "@" cast autocomplete — the cast-name twin of the slash cheat sheet
  // (same panel styles). Tracks the caret so a token being typed mid-draft
  // still resolves; picking a row splices "@Name " and the engine's
  // direct-address router makes that character answer the turn. An active
  // @ token outranks the slash sheet (so "/speak @Ev" shows the cast, as on
  // desktop, where the slash helper only matches a bare "/command" field).
  const [caret, setCaret] = useState(0);
  const [mentionDismissed, setMentionDismissed] = useState(false);
  const mentionable = (cast ?? []).length > 1 ? cast! : [];
  const mentionQuery =
    mentionable.length > 0 ? activeMentionQuery(draft, caret) : null;
  const mentionMatches = mentionQuery
    ? mentionable.filter((c) => mentionNameMatches(c.name, mentionQuery.prefix))
    : [];
  const showMention = !mentionDismissed && mentionMatches.length > 0;
  const showSlash =
    draft.trimStart().startsWith('/') && !slashDismissed && !showMention;

  const insertMention = (name: string) => {
    if (!mentionQuery) return;
    const inserted = `@${name} `;
    const next =
      draft.slice(0, mentionQuery.start) + inserted + draft.slice(caret);
    const newCaret = mentionQuery.start + inserted.length;
    setDraft(next);
    setCaret(newCaret);
    requestAnimationFrame(() => {
      const ta = taRef.current;
      if (ta) {
        ta.focus();
        ta.setSelectionRange(newCaret, newCaret);
      }
    });
  };

  // Auto-grow the textarea with content, capped at ~40% of the viewport (then it
  // scrolls). Resets to one line after sending (draft clears). The transparent
  // textarea sits over a coloured backdrop (live dialogue/action coloring); both
  // are kept the same height so the caret stays glued to the coloured glyphs.
  const taRef = useRef<HTMLTextAreaElement>(null);
  const backdropRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = 'auto';
    const max = Math.round(window.innerHeight * 0.4);
    const h = Math.min(ta.scrollHeight, max);
    ta.style.height = `${h}px`;
    ta.style.overflowY = ta.scrollHeight > max ? 'auto' : 'hidden';
    const bd = backdropRef.current;
    if (bd) {
      bd.style.height = `${h}px`;
      bd.scrollTop = ta.scrollTop;
    }
  }, [draft]);

  // Keep the coloured backdrop scrolled in lock-step with the textarea.
  const syncScroll = () => {
    const bd = backdropRef.current;
    const ta = taRef.current;
    if (bd && ta) bd.scrollTop = ta.scrollTop;
  };

  const send = () => {
    const text = draft.trim();
    if (!text) return;
    setDraft('');
    setSlashDismissed(false);
    setMentionDismissed(false);
    setCaret(0);
    onSend(text);
  };

  return (
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
      {showMention && (
        <div
          className="slash-cheatsheet"
          role="listbox"
          aria-label="Address a character"
        >
          <div className="cheatsheet-head">
            <span>Address a character</span>
            <button className="link-btn" onClick={() => setMentionDismissed(true)}>Close</button>
          </div>
          {mentionMatches.map((c, i) => (
            <button
              key={`${i}-${c.name}`}
              className="cheatsheet-row"
              onClick={() => insertMention(c.name)}
            >
              <span className="cheatsheet-cmd">@{c.name}</span>
              <span className="cheatsheet-desc">
                {c.isHost
                  ? 'Main character — keeps the turn'
                  : c.isLite
                    ? 'Scene Guest — answers in their own reply'
                    : 'Group member — answers this turn'}
              </span>
            </button>
          ))}
        </div>
      )}
      <div className="composer-area">
        <div className="composer-backdrop" ref={backdropRef} aria-hidden="true">
          {renderRpInline(draft, 'c', false)}
          {'\n'}
        </div>
        <textarea
          ref={taRef}
          className="composer-input"
          value={draft}
          spellCheck
          onScroll={syncScroll}
          onChange={(e) => {
            const v = e.target.value;
            const c = e.target.selectionStart ?? v.length;
            setDraft(v);
            setCaret(c);
            if (!v.trimStart().startsWith('/')) setSlashDismissed(false);
            // A dismissed "@" popup comes back once the token is left/retyped.
            if (!activeMentionQuery(v, c)) setMentionDismissed(false);
          }}
          onSelect={(e) => {
            const ta = e.target as HTMLTextAreaElement;
            setCaret(ta.selectionStart ?? draft.length);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Escape' && showMention) {
              e.preventDefault();
              setMentionDismissed(true);
              return;
            }
            if (e.key === 'Escape' && showSlash) {
              e.preventDefault();
              setSlashDismissed(true);
              return;
            }
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              send();
            }
          }}
          placeholder="Message…"
          rows={1}
        />
      </div>
      {canMic && (
        <MicButton
          disabled={isGenerating}
          onText={(t) => setDraft((d) => (d ? `${d} ${t}` : t))}
        />
      )}
      {isGenerating ? (
        <button className="primary" onClick={onStop}>Stop</button>
      ) : (
        <button className="primary" onClick={send} disabled={!draft.trim()}>
          Send
        </button>
      )}
    </div>
  );
}
