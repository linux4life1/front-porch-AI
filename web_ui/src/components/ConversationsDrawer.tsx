// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Conversations slide-over drawer (past sessions + "New chat"). Extracted
// verbatim from ChatPage to keep that page under the file-size cap.

export interface SessionSummary {
  id: string;
  preview: string;
  message_count: number;
  user_message_count: number;
  date: string;
  session_name?: string;
}

function formatDate(iso: string) {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? ''
    : d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function ConversationsDrawer({
  sessions,
  loading,
  activeSessionId,
  onLoad,
  onNew,
  onClose,
}: {
  sessions: SessionSummary[];
  loading: boolean;
  activeSessionId: string | null;
  onLoad: (id: string) => void;
  onNew: () => void;
  onClose: () => void;
}) {
  return (
    <div className="drawer-backdrop" onClick={onClose}>
      <div className="sessions-drawer" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Conversations</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <button className="primary new-chat" onClick={onNew}>+ New chat</button>
        {loading ? (
          <div className="centered"><div className="spinner" /></div>
        ) : sessions.length === 0 ? (
          <p className="muted">No past conversations yet.</p>
        ) : (
          <ul className="conv-list">
            {sessions.map((s) => (
              <li key={s.id}>
                <button
                  className={`conv-item${s.id === activeSessionId ? ' active' : ''}`}
                  onClick={() => onLoad(s.id)}
                >
                  <span className="conv-preview">{s.session_name || s.preview}</span>
                  <span className="conv-meta">
                    {formatDate(s.date)} · {s.message_count} msgs
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
