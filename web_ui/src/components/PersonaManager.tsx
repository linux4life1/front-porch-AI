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

import { useEffect, useRef, useState } from 'react';
import { api, ApiError } from '../api/client';
import { confirmDiscard } from '../hooks/useUnsavedChanges';
import { MakeCharacterDialog } from './library/PersonaConvertDialogs';

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

/** `onDirtyChange` lets the page guard leaving an unsaved persona edit. */
export function PersonaManager({ onDirtyChange }: { onDirtyChange?: (dirty: boolean) => void } = {}) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  // The edit as it was opened; anything else is unsaved.
  const [editBase, setEditBase] = useState<string | null>(null);
  const dirty = edit !== null && JSON.stringify(edit) !== editBase;
  useEffect(() => {
    onDirtyChange?.(dirty);
  }, [dirty, onDirtyChange]);
  const openEdit = (e: EditState) => {
    setEdit(e);
    setEditBase(JSON.stringify(e));
  };
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [makeFrom, setMakeFrom] = useState<PersonaDetail | null>(null);
  const importInput = useRef<HTMLInputElement>(null);

  const load = () =>
    api.get<{ personas: Persona[] }>('/api/personas').then((r) => setPersonas(r.personas)).catch(() => {});

  useEffect(() => {
    void load();
  }, []);

  const apply = (p: Promise<{ personas: Persona[] }>, closeEditor = true) => {
    setBusy(true);
    setError('');
    p.then((r) => {
      setPersonas(r.personas);
      if (closeEditor) setEdit(null);
    })
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Action failed'))
      .finally(() => setBusy(false));
  };

  // Choosing the default or deleting another persona keeps the open edit.
  const select = (id: string) =>
    apply(api.post('/api/personas/select', { id }).then(() => api.get('/api/personas')), false);
  const beginEdit = async (id: string) => {
    if (!confirmDiscard(dirty)) return;
    try {
      const d = await api.get<PersonaDetail>(`/api/personas/${id}/detail`);
      openEdit({ id: d.id, title: d.title, name: d.name, persona: d.persona, birthday: d.birthday ?? '' });
    } catch {
      setError('Could not load persona');
    }
  };
  const beginMakeCharacter = async (id: string) => {
    try {
      setMakeFrom(await api.get<PersonaDetail>(`/api/personas/${id}/detail`));
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

  // Import a persona JSON document (FPAI bundle, SillyTavern V2/V1 export,
  // V2 card — the same formats the desktop's picker feeds the service). The
  // snackbar copy mirrors the desktop's status line.
  const importJson = async (file: File | null) => {
    if (!file) return;
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const r = await api.upload<{ imported: string; personas: Persona[] }>(
        '/api/personas/import',
        file,
      );
      setPersonas(r.personas);
      setNotice(`Imported "${r.imported}" successfully`);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Import failed — unrecognized format');
    } finally {
      setBusy(false);
      if (importInput.current) importInput.current.value = '';
    }
  };

  // Download one persona as the desktop names it (`Ada_Lovelace_FPAIpersona
  // .json`); the server sets the name, this is only the fallback.
  const exportJson = async (p: Persona) => {
    setError('');
    try {
      const { blob, fileName } = await api.getForFile(
        `/api/personas/${p.id}/export.json`,
        `${p.name.replace(/[^\w\s]/g, '').replace(/ /g, '_')}_FPAIpersona.json`,
      );
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  return (
    <section className="card" data-testid="persona-manager">
      <div className="card-head">
        <h3>User personas</h3>
        <button
          className="ghost"
          onClick={() => importInput.current?.click()}
          disabled={busy}
          title="Import a persona JSON file (FPAI bundle, SillyTavern export, character card)"
        >
          Import JSON
        </button>
        <input
          ref={importInput}
          type="file"
          accept=".json,application/json"
          style={{ display: 'none' }}
          data-testid="persona-import-file"
          onChange={(e) => void importJson(e.target.files?.[0] ?? null)}
        />
        <button
          className="ghost"
          onClick={() =>
            confirmDiscard(dirty) &&
            openEdit({ id: null, title: '', name: 'User', persona: '', birthday: '' })
          }
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
                title="Export JSON"
                aria-label={`Export ${p.label} as JSON`}
                onClick={() => void exportJson(p)}
              >
                ⤓
              </button>
              <button
                className="icon-btn"
                title="Make a character"
                aria-label={`Make a character from ${p.label}`}
                onClick={() => beginMakeCharacter(p.id)}
              >
                🧑
              </button>
              <button
                className="icon-btn"
                title="Delete"
                disabled={busy || personas.length <= 1}
                onClick={() => apply(api.post(`/api/personas/${p.id}/delete`), edit?.id === p.id)}
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
            <button onClick={() => confirmDiscard(dirty) && setEdit(null)}>Cancel</button>
            <button className="primary" disabled={busy || !edit.name.trim()} onClick={save}>
              {busy ? 'Saving…' : 'Save persona'}
            </button>
          </div>
        </div>
      )}

      {makeFrom && (
        <MakeCharacterDialog
          personaId={makeFrom.id}
          personaName={makeFrom.name}
          personaText={makeFrom.persona}
          onClose={() => setMakeFrom(null)}
        />
      )}

      {notice && !error && <p className="small" role="status">{notice}</p>}
      {error && <p className="error">{error}</p>}
    </section>
  );
}
