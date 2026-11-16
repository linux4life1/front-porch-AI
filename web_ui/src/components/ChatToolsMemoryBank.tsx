// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Memory section's three links, as on the desktop Memory leaf and in its
// order: Settings, Sources (the memory-sources picker) and Data Bank. In a
// group they speak for the focused member (`?participant=`).

import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { api } from '../api/client';

type Choice = { id: string; name: string };
type SourcesState = {
  available: boolean;
  ownerName?: string;
  selected?: string[];
  choices?: Choice[];
};
type BankEntry = { id: string; title: string; content: string; embedded: boolean };
type BankState = {
  available: boolean;
  ownerName?: string;
  entries?: BankEntry[];
  embedded?: number;
  unembedded?: number;
  note?: string;
};

/** The desktop's file filter for the Data Bank import. */
const ACCEPT = '.txt,.md,.json,.csv,.log,.xml,.html,.yml,.yaml,.pdf';

const words = (s: string) => (s.trim() === '' ? 0 : s.trim().split(/\s+/).length);

function toBase64(buf: ArrayBuffer): string {
  let s = '';
  const bytes = new Uint8Array(buf);
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s);
}

export function MemoryLinks({
  focusedId,
  settings,
}: {
  focusedId?: string | null;
  /** The Settings well (the retrieval sliders), shown under the link. */
  settings: ReactNode;
}) {
  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';
  const [showSettings, setShowSettings] = useState(false);
  const [showSources, setShowSources] = useState(false);
  const [showBank, setShowBank] = useState(false);
  const [sources, setSources] = useState<SourcesState | null>(null);
  const loadedFor = useRef<string | null>(null);

  const loadSources = useCallback(async () => {
    try {
      setSources(await api.get<SourcesState>(`/api/chat/tools/memory/sources${q}`));
      loadedFor.current = q;
    } catch {
      /* no active chat */
    }
  }, [q]);

  // The count in the link follows whoever is focused.
  useEffect(() => {
    void loadSources();
  }, [loadSources]);

  if (sources && !sources.available) return <>{settings}</>;
  const count = sources?.selected?.length ?? 0;

  const toggleSource = async (id: string, selected: boolean) => {
    setSources((s) =>
      s && {
        ...s,
        selected: selected ? [...(s.selected ?? []), id] : (s.selected ?? []).filter((x) => x !== id),
      },
    );
    try {
      setSources(await api.post<SourcesState>(`/api/chat/tools/memory/sources${q}`, { id, selected }));
    } catch {
      void loadSources();
    }
  };

  return (
    <>
      <div className="memory-links">
        <button
          type="button"
          className="memory-link"
          aria-pressed={showSettings}
          onClick={() => setShowSettings((v) => !v)}
        >
          Settings
        </button>
        <button
          type="button"
          className="memory-link"
          aria-pressed={showSources}
          onClick={() => setShowSources((v) => !v)}
        >
          {`Sources${count > 0 ? ` (${count})` : ''}`}
        </button>
        <button type="button" className="memory-link" onClick={() => setShowBank(true)}>
          Data Bank
        </button>
      </div>
      {showSettings && <div className="memory-well">{settings}</div>}
      {showSources && (
        <div className="memory-well">
          <p className="muted small">Include memories from other characters:</p>
          {(sources?.choices ?? []).length === 0 ? (
            <p className="muted small">No other characters available.</p>
          ) : (
            sources!.choices!.map((c) => (
              <label key={c.id} className="tool-toggle">
                <span>{c.name}</span>
                <input
                  type="checkbox"
                  aria-label={`Include memories from ${c.name}`}
                  checked={(sources!.selected ?? []).includes(c.id)}
                  onChange={(e) => void toggleSource(c.id, e.target.checked)}
                />
              </label>
            ))
          )}
        </div>
      )}
      {showBank && <DataBankModal q={q} onClose={() => setShowBank(false)} />}
    </>
  );
}

function DataBankModal({ q, onClose }: { q: string; onClose: () => void }) {
  const [bank, setBank] = useState<BankState | null>(null);
  const [form, setForm] = useState<{ id: string | null; title: string; content: string } | null>(null);
  const [busy, setBusy] = useState('');
  const file = useRef<HTMLInputElement>(null);
  const url = `/api/chat/tools/memory/databank${q}`;

  useEffect(() => {
    let live = true;
    api
      .get<BankState>(url)
      .then((b) => live && setBank(b))
      .catch(() => {});
    return () => {
      live = false;
    };
  }, [url]);

  const act = async (body: Record<string, unknown>, label: string) => {
    setBusy(label);
    try {
      setBank(await api.post<BankState>(url, body));
    } catch {
      /* the list stays as it was */
    } finally {
      setBusy('');
    }
  };

  const save = async () => {
    if (!form || !form.title.trim() || !form.content.trim()) return;
    await act(
      { action: form.id ? 'edit' : 'add', id: form.id, title: form.title, content: form.content },
      'Saving…',
    );
    setForm(null);
  };

  const importFile = async (f: File) => {
    await act({ action: 'import', fileName: f.name, dataBase64: toBase64(await f.arrayBuffer()) }, 'Importing…');
  };

  const entries = bank?.entries ?? [];
  const unembedded = bank?.unembedded ?? 0;
  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div className="modal data-bank" role="dialog" aria-label="Data Bank" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{`Data Bank — ${bank?.ownerName ?? ''}`}</span>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        <p className="muted small">
          {`${entries.length} entries, ${bank?.embedded ?? 0} embedded${unembedded > 0 ? `, ${unembedded} need embedding` : ''}`}
        </p>
        {busy && <p className="muted small">{busy}</p>}
        {bank?.note && <p className="muted small">{bank.note}</p>}
        {form ? (
          <div className="data-bank-form">
            <strong>{form.id ? 'Edit Entry' : 'New Entry'}</strong>
            <label className="field">
              <span className="muted small">Title</span>
              <input
                value={form.title}
                placeholder='e.g., "Backstory", "World Lore", "Character History"'
                onChange={(e) => setForm({ ...form, title: e.target.value })}
              />
            </label>
            <label className="field">
              <span className="muted small">Content</span>
              <textarea
                rows={8}
                value={form.content}
                placeholder="Enter knowledge text..."
                onChange={(e) => setForm({ ...form, content: e.target.value })}
              />
            </label>
            <div className="modal-actions">
              <button onClick={() => setForm(null)}>Cancel</button>
              <button className="primary" disabled={!form.title.trim() || !form.content.trim()} onClick={() => void save()}>
                Save
              </button>
            </div>
          </div>
        ) : (
          <>
            <div className="tool-row">
              <button onClick={() => setForm({ id: null, title: '', content: '' })}>Add Entry</button>
              <button onClick={() => file.current?.click()}>Import File</button>
              {unembedded > 0 && (
                <button disabled={busy !== ''} onClick={() => void act({ action: 'embed' }, 'Embedding…')}>
                  {`Embed (${unembedded})`}
                </button>
              )}
              <input
                ref={file}
                type="file"
                hidden
                accept={ACCEPT}
                aria-label="Import a file into the Data Bank"
                onChange={(e) => {
                  const f = e.target.files?.[0];
                  e.target.value = '';
                  if (f) void importFile(f);
                }}
              />
            </div>
            <p className="muted small">Supports: .txt, .md, .pdf, .json, .csv, .xml, .html, .yml</p>
            {entries.length === 0 ? (
              <div className="data-bank-empty">
                <strong>No entries yet</strong>
                <p className="muted small">
                  Add text or import files to build a knowledge base.
                  <br />
                  RAG retrieves matching entries during conversations.
                </p>
              </div>
            ) : (
              <ul className="data-bank-list">
                {entries.map((e) => (
                  <li key={e.id} className="data-bank-entry">
                    <div className="data-bank-entry-head">
                      <span aria-label={e.embedded ? 'Embedded' : 'Not embedded'}>{e.embedded ? '●' : '○'}</span>
                      <strong>{e.title}</strong>
                      <span className="muted small">{`${words(e.content)}w`}</span>
                      <button
                        className="link-btn"
                        aria-label={`Edit ${e.title}`}
                        onClick={() => setForm({ id: e.id, title: e.title, content: e.content })}
                      >
                        Edit
                      </button>
                      <button
                        className="link-btn"
                        aria-label={`Delete ${e.title}`}
                        onClick={() => void act({ action: 'delete', id: e.id }, 'Deleting…')}
                      >
                        Delete
                      </button>
                    </div>
                    <p className="muted small">
                      {e.content.length > 150 ? `${e.content.substring(0, 150)}...` : e.content}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </div>
    </div>
  );
}
