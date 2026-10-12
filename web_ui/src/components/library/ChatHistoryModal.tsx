// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library Manage Chats — the web twin of the desktop folder/Home dialog.
// Owns fetch / delete / open so CharactersPage does not grow session state.

import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../../api/client';
import type { SessionSummary } from '../ConversationsDrawer';
import { ConfirmDialog } from './LibraryDialogs';

function formatDate(iso: string) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? ''
    : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function ChatHistoryModal({
  characterId,
  groupId,
  onClose,
  onNewChat,
}: {
  characterId?: string;
  groupId?: string;
  onClose: () => void;
  /** Always offered, even with zero or one saved chat. */
  onNewChat: () => void;
}) {
  const navigate = useNavigate();
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [pending, setPending] = useState<SessionSummary | null>(null);

  const load = () => {
    const q = groupId
      ? `groupId=${encodeURIComponent(groupId)}`
      : `characterId=${encodeURIComponent(characterId ?? '')}`;
    return api
      .get<{ sessions: SessionSummary[] }>(`/api/chat/sessions?${q}`)
      .then((r) => setSessions(r.sessions ?? []))
      .catch(() => setSessions([]));
  };

  useEffect(() => {
    setLoading(true);
    void load().finally(() => setLoading(false));
    // characterId / groupId are the modal's identity for this open.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [characterId, groupId]);

  const openSession = async (sessionId: string) => {
    onClose();
    navigate('/chat?opening=1');
    try {
      if (groupId) {
        await api.post('/api/chat/select-group', { groupId });
      } else if (characterId) {
        await api.post('/api/chat/select', { characterId });
      }
      await api.post('/api/chat/session', { sessionId });
      navigate('/chat', { replace: true });
    } catch {
      navigate('/', { replace: true });
    }
  };

  const deleteSession = async (s: SessionSummary) => {
    await api.post('/api/chat/session', {
      action: 'delete',
      sessionId: s.id,
      startReplacement: false,
    });
    await load();
  };

  return (
    <div
      className="drawer-backdrop center"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className="modal chat-history-modal"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <span>Manage Chats</span>
          <button className="link-btn" onClick={onClose}>
            Close
          </button>
        </div>
        <button className="primary new-chat" onClick={onNewChat}>
          + Start new chat
        </button>
        {loading ? (
          <div className="centered">
            <div className="spinner" />
          </div>
        ) : sessions.length === 0 ? (
          <p className="muted">No previous chats found.</p>
        ) : (
          <ul className="conv-list chat-history-list">
            {sessions.map((s) => (
              <li key={s.id} className="conv-row">
                <button className="conv-item" onClick={() => void openSession(s.id)}>
                  <span className="conv-preview">{s.session_name || s.preview}</span>
                  <span className="conv-meta">
                    {formatDate(s.date)} · {s.message_count} msgs
                  </span>
                </button>
                <button
                  type="button"
                  className="icon-btn conv-delete"
                  aria-label="Delete chat"
                  title="Delete chat"
                  onClick={() => setPending(s)}
                >
                  🗑
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      {pending && (
        <ConfirmDialog
          title="Delete Chat?"
          message={`This will permanently delete this chat and all its messages.\n\n"${pending.session_name || pending.preview}"`}
          confirmLabel="Delete"
          danger
          onConfirm={() => {
            const s = pending;
            setPending(null);
            void deleteSession(s);
          }}
          onClose={() => setPending(null)}
        />
      )}
    </div>
  );
}
