// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "What would the writer see?": describe a beat and see which lore entries the
// writer would be handed for it, by meaning when the embedding model is set up
// and by word overlap when it is not. Web twin of LoreSection._testSearch.

import { useState } from 'react';
import { api, ApiError } from '../../../api/client';
import { Dialog } from '../setup/primitives';

interface Hit {
  score: number;
  topic: string;
  detail: string;
  semantic: boolean;
}

export function SearchDialog({ id, onClose }: { id: string; onClose: () => void }) {
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<Hit[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState('');

  const search = async () => {
    if (!query.trim() || busy) return;
    setBusy(true);
    setFailure('');
    try {
      const r = await api.post<{ hits: Hit[] }>(`/api/stories/${id}/lore/search`, { query });
      setHits(r.hits ?? []);
    } catch (e) {
      setFailure(e instanceof ApiError ? e.message : 'The search could not run');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog title="What would the writer see?" testid="lore-search-dialog" onClose={onClose} actions={(
      <button type="button" className="s-btn-ghost" onClick={onClose}>Close</button>
    )}>
      <div className="s-w520">
        <textarea className="s-textarea" rows={2} autoFocus aria-label="Describe a beat" data-testid="lore-search-query"
          placeholder={'Describe a beat, e.g. "Mara haggles at the salt market"'}
          value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <div className="s-row">
        <button type="button" className="s-btn-primary" data-testid="lore-search-go" disabled={!query.trim() || busy}
          onClick={() => { void search(); }}>Search</button>
        {hits && hits.length > 0 && (
          <span className="s-muted s-small">
            {hits[0].semantic ? 'by meaning (embeddings)' : 'by word overlap (embedding model not set up)'}
          </span>
        )}
      </div>
      {failure && <p className="s-error">{failure}</p>}
      {hits && hits.length === 0 && <span className="s-muted s-small">Nothing close enough.</span>}
      {hits?.map((h, i) => (
        <div key={i} className="s-hit">
          <span className="s-mono">{Math.round(h.score * 100)}%</span>
          <span>{h.topic}: {h.detail}</span>
        </div>
      ))}
    </Dialog>
  );
}
