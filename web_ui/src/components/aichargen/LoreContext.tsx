// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Lore context for the AI creator — the web mirror of the desktop lore input.
// Paste wiki/lore URLs (comma-separated) or attach a file (.txt/.md/.pdf/.rtf);
// the server scrapes/extracts the text (shared LoreExtractionService) and it is
// fed to the generator as worldLore so the character gets canon details right.

import { useState, type ChangeEvent } from 'react';
import { api, ApiError } from '../../api/client';
import { type ChargenForm } from './chargenForm';

export function LoreContext({
  form, set,
}: {
  form: ChargenForm; set: (p: Partial<ChargenForm>) => void;
}) {
  const [urls, setUrls] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const append = (text: string) => {
    const t = text.trim();
    if (!t) return;
    set({ worldLore: form.worldLore ? `${form.worldLore}\n\n${t}` : t });
  };

  const fetchUrls = async () => {
    const list = urls.split(',').map((s) => s.trim()).filter(Boolean);
    if (!list.length || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await api.post<{ lore: string; chars: number }>('/api/chargen/lore/urls', { urls: list });
      if (r.lore) { append(r.lore); setUrls(''); }
      else setError('No readable text found at those URLs.');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not fetch those URLs');
    } finally {
      setBusy(false);
    }
  };

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || busy) return;
    setBusy(true);
    setError('');
    try {
      const r = await api.upload<{ lore: string; chars: number }>('/api/chargen/lore/file', file);
      if (r.lore) append(r.lore);
      else setError(`No readable text found in ${file.name}.`);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not read that file');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="cg-config cg-lore">
      <h4 className="cg-subhead">Lore context <span className="muted small">(optional — for accurate canon)</span></h4>
      <p className="muted small">
        Paste wiki/lore URLs (comma-separated) or attach a file. The text is fed to the
        generator so it gets canon details right — great for established universes.
      </p>
      <div className="cg-lore-url">
        <input
          value={urls}
          onChange={(e) => setUrls(e.target.value)}
          placeholder="https://wowpedia.fandom.com/wiki/Sylvanas_Windrunner, …"
          disabled={busy}
        />
        <button type="button" className="primary" onClick={fetchUrls} disabled={busy || !urls.trim()}>
          {busy ? 'Fetching…' : 'Fetch'}
        </button>
      </div>
      <label className="cg-lore-file">
        <span>📎 Attach file (.txt, .md, .pdf, .rtf)</span>
        <input type="file" accept=".txt,.md,.pdf,.rtf,.json,.csv" onChange={onFile} disabled={busy} hidden />
      </label>
      {error && <p className="error">{error}</p>}
      {form.worldLore && (
        <div className="cg-field">
          <span className="cg-field-label">
            Gathered lore — {form.worldLore.length.toLocaleString()} chars{' '}
            <button type="button" className="link-btn" onClick={() => set({ worldLore: '' })}>clear</button>
          </span>
          <textarea rows={6} value={form.worldLore} onChange={(e) => set({ worldLore: e.target.value })} />
        </div>
      )}
    </div>
  );
}
