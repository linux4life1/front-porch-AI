// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// User-persona manager: the web twin of the desktop User Personas page
// (user_persona_page.dart + persona_main_view.dart + persona_list_cards.dart).
// Hero card for the default persona, an "All Personas (N)" grid of cards
// with description previews, a kebab menu per card (Edit / Export JSON /
// Make a Character / Delete), "Make default" on the rest, and page-level
// Import JSON / Export All / New Persona. Thin over the /api/personas
// endpoints (UserPersonaService on the host).
//
// Deliberately does NOT change who the open chat is speaking as — that is the
// chat's own binding, switched from the chat header (see ChatPage's persona
// picker) and stored on the session. Selecting here used to move both at once,
// which meant a background save could stamp a Settings change onto whatever
// chat happened to still be loaded.

import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { api, ApiError } from '../api/client';
import { confirmDiscard } from '../hooks/useUnsavedChanges';
import { MakeCharacterDialog } from './library/PersonaConvertDialogs';

interface Persona {
  id: string;
  label: string;
  name: string;
  /** Card subtitle on the desktop — shown only when non-empty. */
  title?: string;
  /** The persona text; cards clamp it, the hero shows two lines. */
  description?: string;
  hasAvatar?: boolean;
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

// The desktop's PersonaColors._palette (persona_colors.dart). The desktop
// hashes with Dart's String.hashCode, which is salted per run — its persona
// colors already change between restarts — so the web pins the same palette
// with a stable hash and each card keeps its color across reloads.
const PALETTE = [
  '#3B82F6', '#64748B', '#0EA5E9', '#EF4444', '#F59E0B', '#10B981', // theme-keep: the desktop's PersonaColors palette (persona_colors.dart)
  '#06B6D4', '#2563EB', '#F97316', '#84CC16', '#14B8A6', '#059669', // theme-keep: persona identity colours, fixed in every theme
];
const personaColor = (id: string) => {
  let h = 5381;
  for (let i = 0; i < id.length; i++) h = ((h << 5) + h + id.charCodeAt(i)) | 0;
  return PALETTE[Math.abs(h) % PALETTE.length];
};

// Icons.person, the desktop avatar placeholder.
const PersonGlyph = () => (
  <svg viewBox="0 0 24 24" width="55%" height="55%" fill="currentColor" aria-hidden>
    <circle cx="12" cy="8" r="4" />
    <path d="M4 20c0-4 3.6-6.5 8-6.5s8 2.5 8 6.5v1H4z" />
  </svg>
);

/** `onDirtyChange` lets the page guard leaving an unsaved persona edit. */
export function PersonaManager({ onDirtyChange }: { onDirtyChange?: (dirty: boolean) => void } = {}) {
  const [personas, setPersonas] = useState<Persona[]>([]);
  const [edit, setEdit] = useState<EditState>(null);
  const [menuId, setMenuId] = useState<string | null>(null);
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
  // Tapping a card makes it the default — the desktop's card tap.
  const select = (id: string) =>
    apply(api.post('/api/personas/select', { id }).then(() => api.get('/api/personas')), false);
  const beginEdit = async (id: string) => {
    if (!confirmDiscard(dirty)) return;
    setMenuId(null);
    try {
      const d = await api.get<PersonaDetail>(`/api/personas/${id}/detail`);
      openEdit({ id: d.id, title: d.title, name: d.name, persona: d.persona, birthday: d.birthday ?? '' });
    } catch {
      setError('Could not load persona');
    }
  };
  const beginMakeCharacter = async (id: string) => {
    setMenuId(null);
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

  const download = (blob: Blob, fileName: string) => {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    a.click();
    URL.revokeObjectURL(url);
  };

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
    setMenuId(null);
    setError('');
    try {
      const { blob, fileName } = await api.getForFile(
        `/api/personas/${p.id}/export.json`,
        `${p.name.replace(/[^\w\s]/g, '').replace(/ /g, '_')}_FPAIpersona.json`,
      );
      download(blob, fileName);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  // The header's Export icon: every persona in one document, named the way
  // the desktop names its multi-persona file.
  const exportAll = async () => {
    setError('');
    try {
      const { blob, fileName } = await api.getForFile('/api/personas/export-all.json', 'FPAI_personas.json');
      download(blob, fileName);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  const tint = (id: string) => ({ '--pc': personaColor(id) } as CSSProperties);

  return (
    <section className="card" data-testid="persona-manager">
      <div className="card-head">
        <h3>User Personas</h3>
        <button
          className="ghost"
          onClick={() => importInput.current?.click()}
          disabled={busy}
          title="Import Persona (JSON)"
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
        <button className="ghost" onClick={() => void exportAll()} disabled={busy || !personas.length} title="Export Personas (JSON)">
          Export All JSON
        </button>
        <button
          className="primary"
          onClick={() =>
            confirmDiscard(dirty) &&
            openEdit({ id: null, title: '', name: 'User', persona: '', birthday: '' })
          }
        >
          + New Persona
        </button>
      </div>

      {personas.length === 0 && !edit && (
        <div className="persona-empty">
          <span className="persona-empty-av"><PersonGlyph /></span>
          <p className="persona-empty-title">No personas yet</p>
          <p className="muted">
            Create a persona to personalize your AI conversations, or import one from SillyTavern /
            Backyard AI.
          </p>
        </div>
      )}

      {fallback && (
        <div className="persona-hero" style={tint(fallback.id)}>
          <span className="persona-av persona-av-lg">
            {fallback.hasAvatar
              ? <img src={`/api/personas/${fallback.id}/avatar`} alt="" />
              : <PersonGlyph />}
          </span>
          <div className="persona-hero-main">
            <div className="persona-hero-name">
              <strong>{fallback.label}</strong>
              <span className="persona-badge">Default</span>
            </div>
            {!!fallback.title && <div className="persona-hero-sub">{fallback.name}</div>}
            {!!fallback.description && <p className="persona-hero-desc">{fallback.description}</p>}
            <span className="persona-chip">
              <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor" aria-hidden>
                <circle cx="9" cy="8" r="3.4" />
                <path d="M2.5 19c0-3.4 3-5.4 6.5-5.4s6.5 2 6.5 5.4v.6h-13z" />
                <circle cx="17.5" cy="9" r="2.6" />
                <path d="M16 13.9c3 .3 5.5 2.1 5.5 5.1v.6h-3.2c0-2.2-.9-4.2-2.3-5.7z" />
              </svg>
              {personas.length} persona{personas.length === 1 ? '' : 's'}
            </span>
          </div>
          <button
            className="icon-btn"
            title="Edit active persona"
            aria-label={`Edit active persona`}
            onClick={() => void beginEdit(fallback.id)}
          >
            ✎
          </button>
        </div>
      )}

      {personas.length > 0 && (
        <div className="persona-section">
          <span className="persona-tick" aria-hidden />
          All Personas ({personas.length})
        </div>
      )}

      <ul className="persona-grid">
        {personas.map((p) => (
          <li
            key={p.id}
            className={p.default ? 'default' : undefined}
            style={tint(p.id)}
            onClick={() => !p.default && !busy && select(p.id)}
          >
            <div className="persona-card-top">
              <span className="persona-av">
                {p.hasAvatar
                  ? <img src={`/api/personas/${p.id}/avatar`} alt="" />
                  : <PersonGlyph />}
              </span>
              <span className="persona-main">
                <span className="pname">{p.label}</span>
                {!!p.title && <span className="psub">{p.name}</span>}
              </span>
              <button
                className="icon-btn card-kebab"
                title="More actions"
                aria-label={`More actions for ${p.label}`}
                onClick={(e) => {
                  e.stopPropagation();
                  setMenuId(menuId === p.id ? null : p.id);
                }}
              >
                ⋮
              </button>
            </div>
            <p className={`persona-desc${p.description ? '' : ' empty'}`}>
              {p.description || 'No description'}
            </p>
            <div className="persona-card-foot">
              {p.default
                ? <span className="persona-badge">Default</span>
                : (
                  <button
                    className="persona-make"
                    onClick={(e) => {
                      e.stopPropagation();
                      select(p.id);
                    }}
                  >
                    Make default
                  </button>
                )}
            </div>
            {menuId === p.id && (
              <>
                <div
                  className="card-menu-backdrop"
                  onClick={(e) => {
                    e.stopPropagation();
                    setMenuId(null);
                  }}
                />
                <div className="card-menu persona-card-menu" role="menu" onClick={(e) => e.stopPropagation()}>
                  <button className="card-menu-item" role="menuitem" aria-label={`Edit ${p.label}`} onClick={() => void beginEdit(p.id)}>
                    <span className="cmi-icon" aria-hidden>✎</span> Edit
                  </button>
                  <button
                    className="card-menu-item"
                    role="menuitem"
                    aria-label={`Export ${p.label} as JSON`}
                    onClick={() => void exportJson(p)}
                  >
                    <span className="cmi-icon" aria-hidden>⤓</span> Export JSON
                  </button>
                  <button
                    className="card-menu-item"
                    role="menuitem"
                    aria-label={`Make a character from ${p.label}`}
                    onClick={() => void beginMakeCharacter(p.id)}
                  >
                    <span className="cmi-icon" aria-hidden>🧑</span> Make a Character
                  </button>
                  {personas.length > 1 && (
                    <button
                      className="card-menu-item danger"
                      role="menuitem"
                      disabled={busy}
                      onClick={() => {
                        setMenuId(null);
                        apply(api.post(`/api/personas/${p.id}/delete`), edit?.id === p.id);
                      }}
                    >
                      <span className="cmi-icon" aria-hidden>🗑</span> Delete
                    </button>
                  )}
                </div>
              </>
            )}
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
