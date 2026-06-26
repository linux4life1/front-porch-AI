// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Story bible dashboard: view the generated structure (concept, cast, threads,
// lore, acts), drive the pipeline (architect / act-structure / autopilot) with
// live progress over the WS hub, export, and jump to the structure/writer.

import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';

export function StoryDashboardPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, setError, run } = useStory(id);

  const exportAs = async (format: 'text' | 'markdown') => {
    try {
      const r = await api.get<{ text: string }>(`/api/stories/${id}/export?format=${format}`);
      const blob = new Blob([r.text], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${p?.title || 'story'}.${format === 'markdown' ? 'md' : 'txt'}`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Export failed');
    }
  };

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  const busy = status?.running ?? false;
  const hasBible = p.concept.trim() !== '' && (p.cast.length > 0 || p.status_quo.trim() !== '');
  const hasActs = p.acts.length > 0;

  return (
    <div className="page">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate('/stories')}>← Stories</button>
        <h2>{p.title}</h2>
        <button className="ghost small" onClick={() => navigate(`/stories/${id}/setup`)}>Edit setup</button>
      </div>

      {busy && (
        <div className="card story-progress" aria-live="polite">
          <div className="spinner small" />
          <div>
            <strong>{status?.step || 'Working'}</strong>
            <p className="muted small">{status?.status}{status?.tokens ? ` · ${status.tokens} tokens` : ''}</p>
          </div>
        </div>
      )}
      {error && <p className="error">{error}</p>}

      <section className="card">
        <h3>Pipeline</h3>
        <div className="btn-row">
          {p.use_chat_history && (
            <button className="ghost" disabled={busy} onClick={() => run('chat-distiller')}>Distill chat history</button>
          )}
          <button className="primary" disabled={busy} onClick={() => run('story-architect')}>
            {hasBible ? 'Regenerate bible' : 'Generate story bible'}
          </button>
          <button className="ghost" disabled={busy || !hasBible} onClick={() => run('act-structure')}>
            {hasActs ? 'Regenerate acts' : 'Generate act structure'}
          </button>
          <button className="ghost" disabled={busy} onClick={() => run('autopilot')}>Autopilot (everything)</button>
        </div>
        {hasActs && (
          <div className="btn-row" style={{ marginTop: 10 }}>
            <button className="primary" onClick={() => navigate(`/stories/${id}/structure`)}>Structure &amp; write →</button>
            {p.prose && Object.keys(p.prose).length > 0 && (
              <button className="ghost" onClick={() => navigate(`/stories/${id}/read`)}>Read 📖</button>
            )}
          </div>
        )}
      </section>

      {hasBible && (
        <>
          <section className="card">
            <h3>Concept</h3>
            {p.concept && <p>{p.concept}</p>}
            {p.status_quo && <p><strong>Status quo:</strong> {p.status_quo}</p>}
            {p.inciting_incident && <p><strong>Inciting incident:</strong> {p.inciting_incident}</p>}
            {p.themes && <p><strong>Themes:</strong> {p.themes}</p>}
            {(p.style?.genre || p.style?.mood) && (
              <p className="muted small">{[p.style.genre, p.style.mood].filter(Boolean).join(' · ')}</p>
            )}
          </section>

          {p.cast.length > 0 && (
            <section className="card">
              <h3>Cast</h3>
              {p.cast.map((c, i) => (
                <div key={i} className="story-cast-row">
                  <strong>{c.name}</strong> <span className="muted small">{c.role}</span>
                  <p className="muted small">{c.description}</p>
                </div>
              ))}
            </section>
          )}

          {p.threads.length > 0 && (
            <section className="card">
              <h3>Threads</h3>
              {p.threads.map((t) => (
                <p key={t.id}><strong>{t.name}:</strong> <span className="muted">{t.description}</span></p>
              ))}
            </section>
          )}

          {p.lore.length > 0 && (
            <section className="card">
              <h3>Lore</h3>
              <div className="chip-select">
                {p.lore.map((l, i) => <span key={i} className="chip" title={l.detail}>{l.topic}</span>)}
              </div>
            </section>
          )}

          {hasActs && (
            <section className="card">
              <h3>Acts</h3>
              {p.acts.map((a) => (
                <div key={a.number} className="story-act-row">
                  <strong>Act {a.number}: {a.title}</strong>
                  <p className="muted small">{a.description}</p>
                </div>
              ))}
            </section>
          )}

          <section className="card">
            <h3>Export</h3>
            <div className="btn-row">
              <button className="ghost" onClick={() => exportAs('text')}>Download .txt</button>
              <button className="ghost" onClick={() => exportAs('markdown')}>Download .md</button>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
