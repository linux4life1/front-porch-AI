// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// User-persona manager: choose the DEFAULT persona new chats start as, create
// new ones, edit and delete existing ones. Thin over the /api/personas endpoints
// (UserPersonaService on the host).
//
// Deliberately does NOT change who the open chat is speaking as — that is the
// chat's own binding, switched from the chat header (see ChatPage's persona
// picker) and stored on the session. Selecting here used to move both at once,
// which meant a background save could stamp a Settings change onto whatever
// chat happened to still be loaded.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

interface Persona {
  id: string;
  label: string;
  name: string;
  /** Who the CURRENT chat is speaking as (the in-chat switcher's answer). */
  active: boolean;
  /** Who a NEW chat starts as — what this Settings surface controls. */
  default: boolean;
}
interface PersonaDetail {
  id: string;
  title: string;
  name: string;
  persona: string;
  birthday?: string;
}

type EditState = { id: string | null; title: string; name: string; persona: string; birthday: string } | null;

export function PersonaManager() {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const load = () =>
    api.get<{ personas: Persona[] }>('/api/personas').then((r) => setPersonas(r.personas)).catch(() => {});

  useEffect(() => {
    void load();
  }, []);

  const apply = (p: Promise<{ personas: Persona[] }>) => {
    setBusy(true);
    setError('');
    p.then((r) => {
      setPersonas(r.personas);
      setEdit(null);
    })
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Action failed'))
      .finally(() => setBusy(false));
  };

  const select = (id: string) => apply(api.post('/api/personas/select', { id }).then(() => api.get('/api/personas')));
  const beginEdit = async (id: string) => {
    try {
      const d = await api.get<PersonaDetail>(`/api/personas/${id}/detail`);
      setEdit({ id: d.id, title: d.title, name: d.name, persona: d.persona, birthday: d.birthday ?? '' });
    } catch {
      setError('Could not load persona');
    }
  };
  const save = () => {
    if (!edit) return;
    const body = { title: edit.title, name: edit.name, persona: edit.persona, birthday: edit.birthday };
    apply(
      edit.id
        ? api.post(`/api/personas/${edit.id}`, body)
        : api.post('/api/personas/create', body),
    );
  };

  const fallback = personas.find((p) => p.default);

  return (
    <section className="card">
      <div className="card-head">
        <h3>User personas</h3>
        <button
          className="ghost"
          onClick={() => setEdit({ id: null, title: '', name: 'User', persona: '', birthday: '' })}
        >
          + New
        </button>
      </div>

      {personas.length > 0 && (
        <label>
          Default persona for new chats
          <select value={fallback?.id ?? ''} onChange={(e) => select(e.target.value)} disabled={busy}>
            {personas.map((p) => (
              <option key={p.id} value={p.id}>{p.label}</option>
            ))}
          </select>
        </label>
      )}

      <ul className="persona-list">
        {personas.map((p) => (
          <li key={p.id} className={p.default ? 'active' : undefined}>
            <span className="persona-av" aria-hidden>
              {(p.name || p.label || '?').charAt(0).toUpperCase()}
            </span>
            <span className="persona-main">
              <span className="pname">{p.label}</span>
              {p.default && <span className="pactive">Default</span>}
            </span>
            <span className="persona-actions">
              <button className="icon-btn" title="Edit" onClick={() => beginEdit(p.id)}>✎</button>
              <button
                className="icon-btn"
                title="Delete"
                disabled={busy || personas.length <= 1}
                onClick={() => apply(api.post(`/api/personas/${p.id}/delete`))}
              >
                🗑
              </button>
            </span>
          </li>
        ))}
      </ul>

      {edit && (
        <div className="persona-edit">
          <h4 className="section-label">{edit.id ? 'Edit persona' : 'New persona'}</h4>
          <label>
            Title (optional)
            <input value={edit.title} onChange={(e) => setEdit({ ...edit, title: e.target.value })} />
          </label>
          <label>
            Name
            <input value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} />
          </label>
          <label>
            Birthday
            <input
              type="date"
              value={edit.birthday}
              onChange={(e) => {
                const raw = e.target.value;
                if (/^\d{4}-02-29$/.test(raw)) return;
                setEdit({ ...edit, birthday: raw });
              }}
            />
          </label>
          <label>
            Persona
            <textarea
              rows={4}
              value={edit.persona}
              onChange={(e) => setEdit({ ...edit, persona: e.target.value })}
              placeholder="How the AI should picture you…"
            />
          </label>
          <div className="tool-row">
            <button onClick={() => setEdit(null)}>Cancel</button>
            <button className="primary" disabled={busy || !edit.name.trim()} onClick={save}>
              {busy ? 'Saving…' : 'Save persona'}
            </button>
          </div>
        </div>
      )}

      {error && <p className="error">{error}</p>}
    </section>
  );
}
