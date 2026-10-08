// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Choose a chat…": every 1:1 chat the user has written in, newest first,
// with a search box, as a studio dialog. Web twin of
// lib/ui/story_setup/chat_source_picker.dart; the list itself is the
// desktop's (GET /api/stories/chat-sources).

import { useEffect, useMemo, useState } from 'react';
import { api } from '../../../api/client';
import { formatRelativeTime } from '../relativeTime';
import { Chip } from '../StudioShell';
import { characterAvatar, loadCharacters } from './useSetupData';
import type { CharacterRow, ChatSource } from './draft';
import { Avatar, Dialog } from './primitives';

export interface ChatSourceRow {
  character_id: string;
  character_name: string;
  session_id: string;
  session_name: string;
  date: string;
  message_count: number;
  short: boolean;
}

/** How many chats the list shows at once, same as the desktop picker; search narrows the rest. */
export const PAGE_SIZE = 50;

/** Rows whose character or chat name contains every word of the query. Twin of filterChatSources. */
export function filterChatSources(rows: ChatSourceRow[], query: string): ChatSourceRow[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return rows;
  return rows.filter((r) => {
    const hay = `${r.character_name} ${r.session_name}`.toLowerCase();
    return words.every((w) => hay.includes(w));
  });
}

export function ChatSourcePicker({ onPick, onClose }: {
  onPick: (source: ChatSource) => void;
  onClose: () => void;
}) {
  const [rows, setRows] = useState<ChatSourceRow[] | null>(null);
  const [characters, setCharacters] = useState<Map<string, CharacterRow>>(new Map());
  const [query, setQuery] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await api.get<{ chats: ChatSourceRow[] }>('/api/stories/chat-sources');
        if (live) setRows(r.chats);
      } catch {
        if (live) setError('Could not load your chats. Check that the app is running, then try again.');
        return;
      }
      try {
        // Portraits only; the list works without them.
        const chars = await loadCharacters();
        if (live) setCharacters(new Map(chars.map((c) => [c.id, c])));
      } catch { /* initials stand in */ }
    })();
    return () => { live = false; };
  }, []);

  const found = useMemo(() => filterChatSources(rows ?? [], query), [rows, query]);
  const shown = found.slice(0, PAGE_SIZE);

  return (
    <Dialog title="Start from a chat" wide onClose={onClose} testid="story-chat-picker"
      actions={<button type="button" className="s-btn-ghost" onClick={onClose}>Cancel</button>}>
      {error ? <div className="s-error">{error}</div>
        : rows === null ? <div className="body">Loading your chats…</div>
        : rows.length === 0 ? <div className="body">No chats yet. Talk with a character first, then come back.</div>
        : (
          <div className="s-col" style={{ gap: 2 }}>
            <input type="text" autoFocus placeholder="Search by character or chat name" value={query}
              data-testid="story-chat-search" aria-label="Search chats" style={{ marginBottom: 6 }}
              onChange={(e) => setQuery(e.target.value)} />
            {found.length === 0 && <div className="body s-muted">No chat matches that search.</div>}
            {shown.map((r) => {
              const character = characters.get(r.character_id);
              return (
                <button key={r.session_id} type="button" className="s-listrow" data-testid={`story-chat-${r.session_id}`}
                  onClick={() => onPick({
                    characterId: r.character_id,
                    characterName: r.character_name,
                    sessionId: r.session_id,
                    messageCount: r.message_count,
                    faithful: true,
                  })}>
                  <Avatar name={r.character_name} src={character ? characterAvatar(character) : undefined} />
                  <span className="s-grow">
                    <b className="s-ell" style={{ display: 'block' }}>{r.character_name}</b>
                    <span className="s-muted s-small s-ell" style={{ display: 'block' }}>
                      {[r.session_name, formatRelativeTime(r.date), `${r.message_count} messages`].filter(Boolean).join(' · ')}
                    </span>
                  </span>
                  {r.short && <Chip tone="honey" title="Fewer than 20 messages. There may not be enough here for a story.">short chat</Chip>}
                </button>
              );
            })}
            {found.length > shown.length && (
              <div className="s-muted s-small" style={{ marginTop: 6 }}>
                Showing {shown.length} of {found.length} chats. Search to narrow them down.
              </div>
            )}
          </div>
        )}
    </Dialog>
  );
}
