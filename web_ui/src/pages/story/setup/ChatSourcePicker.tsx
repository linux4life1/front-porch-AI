// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Choose a chat…": every 1:1 chat, newest first, as a studio dialog. Web
// twin of lib/ui/story_setup/chat_source_picker.dart.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import { formatRelativeTime } from '../relativeTime';
import { characterAvatar } from './useSetupData';
import type { CharacterRow, ChatSource } from './draft';
import { Avatar, Dialog } from './primitives';

interface SessionRow {
  id: string;
  date: string;
  session_name?: string;
  message_count?: number;
}

interface ChatRow {
  character: CharacterRow;
  session: SessionRow;
}

/** How many chats the list shows (newest first), same as the desktop picker. */
const MAX_ROWS = 30;

export function ChatSourcePicker({ onPick, onClose }: {
  onPick: (source: ChatSource) => void;
  onClose: () => void;
}) {
  const [rows, setRows] = useState<ChatRow[] | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const chars = await api.get<CharacterRow[]>('/api/characters');
        const perCharacter = await Promise.all(chars.map(async (character) => {
          try {
            const r = await api.get<{ sessions: SessionRow[] }>(`/api/chat/sessions?characterId=${encodeURIComponent(character.id)}`);
            return r.sessions.map((session) => ({ character, session }));
          } catch {
            return [];
          }
        }));
        const all = perCharacter.flat().sort((a, b) => Date.parse(b.session.date) - Date.parse(a.session.date));
        if (live) setRows(all.slice(0, MAX_ROWS));
      } catch {
        if (live) setError('Could not load your chats. Check that the app is running, then try again.');
      }
    })();
    return () => { live = false; };
  }, []);

  return (
    <Dialog title="Start from a chat" wide onClose={onClose} testid="story-chat-picker"
      actions={<button type="button" className="s-btn-ghost" onClick={onClose}>Cancel</button>}>
      {error ? <div className="s-error">{error}</div>
        : rows === null ? <div className="body">Loading your chats…</div>
        : rows.length === 0 ? <div className="body">No chats yet. Talk with a character first, then come back.</div>
        : (
          <div className="s-col" style={{ gap: 2 }}>
            {rows.map(({ character, session }) => (
              <button key={session.id} type="button" className="s-listrow" data-testid={`story-chat-${session.id}`}
                onClick={() => onPick({
                  characterId: character.id,
                  characterName: character.name,
                  sessionId: session.id,
                  messageCount: session.message_count ?? 0,
                  faithful: true,
                })}>
                <Avatar name={character.name} src={characterAvatar(character)} />
                <span className="s-grow">
                  <b className="s-ell" style={{ display: 'block' }}>{character.name}</b>
                  <span className="s-muted s-small s-ell" style={{ display: 'block' }}>
                    {[session.session_name, formatRelativeTime(session.date)].filter(Boolean).join(' · ')}
                  </span>
                </span>
              </button>
            ))}
          </div>
        )}
    </Dialog>
  );
}
