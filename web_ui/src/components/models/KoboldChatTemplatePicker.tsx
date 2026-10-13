// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';
import { api } from '../../api/client';
import type { LocalModel } from './KoboldStatusCard';

export function KoboldChatTemplatePicker({ preset, onSaved }: {
  preset: NonNullable<LocalModel['preset']>;
  onSaved: (card: LocalModel) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [saved, setSaved] = useState(false);
  const name = preset.chatTemplate?.split(/[\\/]/).pop() || '';
  async function save(file?: File) {
    setError('');
    setSaved(false);
    setBusy(true);
    try {
      if (file && (!file.name.toLowerCase().endsWith('.jinja') ||
          file.size === 0 || file.size > 64 * 1024)) {
        throw new Error('Choose a nonempty .jinja text file up to 64 KiB.');
      }
      const card = await api.post<LocalModel>('/api/backend/local-model/chat-template', {
        preset: preset.path,
        name: file?.name ?? null,
        content: file ? await file.text() : null,
      });
      onSaved(card);
      setSaved(true);
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : 'The template could not be saved.');
    } finally {
      setBusy(false);
    }
  }
  return <div className="kc-plain" aria-labelledby="kc-template-heading">
    <h4 id="kc-template-heading">Chat template</h4>
    <p>{name || 'Uses the template embedded in the GGUF.'}</p>
    {preset.chatTemplateEditable ? <div className="kc-template-actions">
      <label className="kc-label" htmlFor="kc-template-file">Upload .jinja file</label>
      <input id="kc-template-file" type="file" accept=".jinja" disabled={busy}
        onChange={event => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = '';
          if (file) void save(file);
        }} />
      {name && <button className="btn" type="button" disabled={busy}
        onClick={() => void save()}>Use embedded template</button>}
    </div> : <p>Edit this preset on desktop, or select a preset in the host engine folder.</p>}
    <p className="kc-words">A custom template overrides the GGUF template.
      Stop and restart KoboldCpp after saving to apply the change.</p>
    {busy && <p role="status">Saving template…</p>}
    {saved && <p role="status">Saved. Restart KoboldCpp to apply the template change.</p>}
    {error && <p role="alert">{error}</p>}
  </div>;
}
