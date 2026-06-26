// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Act → scene → beat structure tree. Generate missing levels and jump into the
// per-scene prose writer. Mirrors the desktop StoryStructurePage.

import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';

export function StoryStructurePage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run } = useStory(id);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;

  return (
    <div className="page">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate(`/stories/${id}`)}>← {p.title}</button>
        <h2>Structure</h2>
        {p.prose && Object.keys(p.prose).length > 0 && (
          <button className="ghost small" onClick={() => navigate(`/stories/${id}/read`)}>Read 📖</button>
        )}
      </div>

      {busy && (
        <div className="card story-progress" aria-live="polite">
          <div className="spinner small" />
          <div><strong>{status?.step || 'Working'}</strong>
            <p className="muted small">{status?.status}{status?.tokens ? ` · ${status.tokens} tokens` : ''}</p></div>
        </div>
      )}
      {error && <p className="error">{error}</p>}

      {p.acts.map((act, ai) => {
        const scenes = p.scenes[String(ai)] ?? [];
        return (
          <section key={ai} className="card">
            <div className="page-head">
              <h3>Act {act.number}: {act.title}</h3>
              <button className="ghost small" disabled={busy} onClick={() => run('full-act', { actIndex: ai })}>
                Generate full act
              </button>
            </div>
            {act.description && <p className="muted small">{act.description}</p>}

            {scenes.length === 0 ? (
              <button className="ghost" disabled={busy} onClick={() => run('scene-weaver', { actIndex: ai })}>
                Generate scenes
              </button>
            ) : (
              scenes.map((sc, si) => {
                const beats = p.beats[`${ai}-${si}`] ?? [];
                const proseCount = Object.keys(p.prose).filter((k) => k.startsWith(`${ai}-${si}-`)).length;
                return (
                  <div key={si} className="story-scene-row">
                    <div className="scene-head">
                      <strong>Scene {sc.number}: {sc.title}</strong>
                      {sc.location && <span className="muted small"> · {sc.location}</span>}
                      <span className={`valence v${sc.valence >= 0 ? 'pos' : 'neg'}`}>{sc.valence > 0 ? `+${sc.valence}` : sc.valence}</span>
                    </div>
                    {sc.description && <p className="muted small">{sc.description}</p>}
                    <div className="btn-row">
                      {beats.length === 0 ? (
                        <button className="ghost small" disabled={busy} onClick={() => run('beat-director', { actIndex: ai, sceneIndex: si })}>
                          Generate beats
                        </button>
                      ) : (
                        <>
                          <span className="muted small">{beats.length} beats · {proseCount}/{beats.length} written</span>
                          <button className="ghost small" disabled={busy} onClick={() => run('auto-write-scene', { actIndex: ai, sceneIndex: si })}>
                            Auto-write
                          </button>
                          <button className="ghost small" onClick={() => navigate(`/stories/${id}/write/${ai}/${si}`)}>
                            Open writer →
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                );
              })
            )}
          </section>
        );
      })}
    </div>
  );
}
