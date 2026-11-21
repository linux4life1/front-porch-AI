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
import { api, ApiError, isTimeout } from '../api/client';
import { confirmDiscard } from '../hooks/useUnsavedChanges';
import { MakeCharacterDialog } from './library/PersonaConvertDialogs';
import { PersonaEditForm, type PersonaDraft } from './PersonaEditForm';

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

type EditState = PersonaDraft | null;

// A persona write is one row on the host — milliseconds when it is healthy.
// Past this the host is stalled (a busy library, a sleeping laptop), and an
// endless "Saving…" read as a broken button; say so and keep the text.
const WRITE_TIMEOUT_MS = 20_000;
const write = <T,>(path: string, body?: unknown) =>
  api.post<T>(path, body, { timeoutMs: WRITE_TIMEOUT_MS });
const STALLED =
  'Front Porch did not answer within 20 seconds, so this may not have saved. ' +
  'Your text is still here — try again in a moment.';

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
  // A failed or timed-out read must not pass for "No personas yet".
  const [loadState, setLoadState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [edit, setEdit] = useState<EditState>(null);
  // Ids listed when a NEW persona's form opened: a save that timed out may
  // still land, and Save again must not make it twice.
  const [idsAtOpen, setIdsAtOpen] = useState<Set<string>>(new Set());
  const [menuId, setMenuId] = useState<string | null>(null);
  // The edit as it was opened; anything else is unsaved.
  const [editBase, setEditBase] = useState<string | null>(null);
  const dirty = edit !== null && JSON.stringify(edit) !== editBase;
  useEffect(() => {
    onDirtyChange?.(dirty);
  }, [dirty, onDirtyChange]);
  const sectionRef = useRef<HTMLElement>(null);
  const openEdit = (e: EditState) => {
    setEdit(e);
    setEditBase(JSON.stringify(e));
    setIdsAtOpen(new Set(personas.map((p) => p.id)));
    setError('');
    setNotice('');
    // The form replaces the list; bring its top into view wherever the
    // list was scrolled to (a card thirty rows down opens Edit too).
    sectionRef.current?.scrollIntoView?.({ block: 'start' });
  };
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [makeFrom, setMakeFrom] = useState<PersonaDetail | null>(null);
  const importInput = useRef<HTMLInputElement>(null);

  const load = () =>
    api
      .get<{ personas: Persona[] }>('/api/personas')
      .then((r) => {
        setPersonas(r.personas);
        setLoadState('ready');
      })
      .catch((e: unknown) => {
        console.warn('[personas] list failed', e);
        setLoadState('error');
      });

  useEffect(() => {
    void load();
  }, []);

  const apply = (p: Promise<{ personas: Persona[] }>, closeEditor = true) => {
    setBusy(true);
    setError('');
    p.then((r) => {
      setPersonas(r.personas);
      setLoadState('ready');
      if (closeEditor) setEdit(null);
    })
      .catch((e: unknown) => {
        if (isTimeout(e)) {
          setError(STALLED);
          // The host may finish late; the list catches up when it does.
          void load();
        } else {
          setError(e instanceof ApiError ? e.message : 'Action failed');
        }
      })
      .finally(() => setBusy(false));
  };

  // Tapping a card makes it the default — the desktop's card tap. (The grid
  // is hidden while a form is open, so no list action races an edit.)
  const select = (id: string) =>
    apply(write('/api/personas/select', { id }).then(() => api.get('/api/personas')), false);
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
    // A create that timed out and then landed is already in the list: done,
    // not a second copy.
    const landed =
      !edit.id &&
      personas.some(
        (p) => !idsAtOpen.has(p.id) && p.name === edit.name && (p.description ?? '') === edit.persona,
      );
    if (landed) {
      setEdit(null);
      setError('');
      setNotice('Persona saved successfully');
      return;
    }
    const body = { title: edit.title, name: edit.name, persona: edit.persona, birthday: edit.birthday };
    setNotice('');
    apply(
      (edit.id
        ? write<{ personas: Persona[] }>(`/api/personas/${edit.id}`, body)
        : write<{ personas: Persona[] }>('/api/personas/create', body)
      ).then((r) => {
        setNotice('Persona saved successfully');
        return r;
      }),
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
    <section className="card" data-testid="persona-manager" ref={sectionRef}>
      {edit ? (
        // The desktop's AppBar while editing: back arrow, "Create Persona" /
        // "Edit Persona", and no page actions.
        <div className="card-head persona-edit-head">
          <button
            className="icon-btn"
            aria-label="Back to personas"
            title="Back"
            onClick={() => confirmDiscard(dirty) && setEdit(null)}
          >
            ←
          </button>
          <h3>{edit.id ? 'Edit Persona' : 'Create Persona'}</h3>
        </div>
      ) : (
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
              openEdit({ id: null, title: '', name: '', persona: '', birthday: '' })
            }
          >
            + New Persona
          </button>
        </div>
      )}

      {edit && (
        <PersonaEditForm
          draft={edit}
          busy={busy}
          onChange={setEdit}
          onCancel={() => confirmDiscard(dirty) && setEdit(null)}
          onSave={save}
        />
      )}

      {!edit && loadState === 'loading' && (
        <p className="muted" role="status">Loading personas…</p>
      )}

      {!edit && loadState === 'error' && (
        <div className="persona-load-error" role="alert">
          <p className="error">
            Could not load your personas — Front Porch did not answer. Nothing has been deleted.
          </p>
          <button
            onClick={() => {
              setLoadState('loading');
              void load();
            }}
          >
            Try again
          </button>
        </div>
      )}

      {!edit && loadState === 'ready' && personas.length === 0 && (
        <div className="persona-empty">
          <span className="persona-empty-av"><PersonGlyph /></span>
          <p className="persona-empty-title">No personas yet</p>
          <p className="muted">
            Create a persona to personalize your AI conversations, or import one from SillyTavern /
            Backyard AI.
          </p>
        </div>
      )}

      {!edit && fallback && (
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

      {!edit && personas.length > 0 && (
        <div className="persona-section">
          <span className="persona-tick" aria-hidden />
          All Personas ({personas.length})
        </div>
      )}

      {!edit && (
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
                          apply(write(`/api/personas/${p.id}/delete`));
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
      )}

      {makeFrom && (
        <MakeCharacterDialog
          personaId={makeFrom.id}
          personaName={makeFrom.name}
          personaText={makeFrom.persona}
          onClose={() => setMakeFrom(null)}
        />
      )}

      {notice && !error && <p className="small" role="status" data-testid="persona-save-notice">{notice}</p>}
      {error && <p className="error">{error}</p>}
    </section>
  );
}
