// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-chat persona switcher: who YOU are in this conversation.
//
// The desktop counterpart is the avatar left of the message box. Web only had
// the Settings persona list, which now sets the DEFAULT for new chats and no
// longer touches the open chat — so without this, a web user could not change
// who they were in a conversation at all.
//
// Posts to /api/chat/persona (not /api/personas/select): the host binds the
// session to the chosen persona and saves immediately, so the change survives
// a reload even if you say nothing else.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

interface Persona {
  id: string;
  label: string;
  name: string;
  active: boolean;
  default: boolean;
  hasAvatar?: boolean;
}

export function ChatPersonaModal({
  onClose,
  onChanged,
}: {
  onClose: () => void;
  /** Called after a successful switch so the page can refresh chat state. */
  onChanged: () => Promise<void> | void;
}) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .get<{ personas: Persona[] }>('/api/personas')
      .then((r) => setPersonas(r.personas))
      .catch(() => setError('Could not load personas'));
  }, []);

  const use = async (id: string) => {
    setBusy(true);
    setError('');
    try {
      await api.post('/api/chat/persona', { id });
      await onChanged();
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not switch persona');
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Speak as…</span>
          <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
        </div>
        <p className="muted small">
          Changes who you are in this conversation only. The default for new chats lives in
          Settings.
        </p>
        {error && <p className="error">{error}</p>}
        <ul className="persona-list">
          {personas.map((p) => (
            <li key={p.id} className={p.active ? 'active' : undefined}>
              <span className="persona-av" aria-hidden>
                {p.hasAvatar
                  ? <img src={`/api/personas/${p.id}/avatar`} alt="" />
                  : (p.name || p.label || '?').charAt(0).toUpperCase()}
              </span>
              <span className="persona-main">
                <span className="pname">{p.label}</span>
                {p.active && <span className="pactive">This chat</span>}
              </span>
              <span className="persona-actions">
                {!p.active && (
                  <button className="link-btn" disabled={busy} onClick={() => use(p.id)}>
                    Use in this chat
                  </button>
                )}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
