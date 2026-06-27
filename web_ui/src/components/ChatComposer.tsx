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

export function ChatComposer({
  onSend,
  onStop,
  isGenerating,
  canMic,
}: {
  onSend: (text: string) => void;
  onStop: () => void;
  isGenerating: boolean;
  canMic: boolean;
}) {
  const [draft, setDraft] = useState('');
  const [slashDismissed, setSlashDismissed] = useState(false);
  const showSlash = draft.trimStart().startsWith('/') && !slashDismissed;

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
