// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Beat-by-beat prose writer for one scene: view each beat's draft/final prose,
// regenerate a single beat, generate beats, or auto-write the whole scene.
// Mirrors the desktop StoryWriterPage.

import { useNavigate, useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { SpeakButton } from '../components/VoiceControls';

export function StoryWriterPage() {
  const { id = '', act = '0', scene = '0' } = useParams();
  const ai = Number(act);
  const si = Number(scene);
  const navigate = useNavigate();
  const { project: p, status, error, run } = useStory(id);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;
  const sc = p.scenes[String(ai)]?.[si];
  const beats = p.beats[`${ai}-${si}`] ?? [];

  return (
    <div className="page">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate(`/stories/${id}/structure`)}>← Structure</button>
        <h2>{sc ? `Scene ${sc.number}: ${sc.title}` : 'Scene'}</h2>
      </div>

      {busy && (
        <div className="card story-progress" aria-live="polite">
          <div className="spinner small" />
          <div><strong>{status?.step || 'Working'}</strong>
            <p className="muted small">{status?.status}{status?.tokens ? ` · ${status.tokens} tokens` : ''}</p></div>
        </div>
      )}
      {error && <p className="error">{error}</p>}

      <div className="btn-row" style={{ marginBottom: 12 }}>
        {beats.length === 0 ? (
          <button className="primary" disabled={busy} onClick={() => run('beat-director', { actIndex: ai, sceneIndex: si })}>
            Generate beats
          </button>
        ) : (
          <button className="primary" disabled={busy} onClick={() => run('auto-write-scene', { actIndex: ai, sceneIndex: si })}>
            Auto-write all beats
          </button>
        )}
      </div>

      {beats.map((b, bi) => {
        const prose = p.prose[`${ai}-${si}-${bi}`];
        const text = prose?.final || prose?.draft || '';
        return (
          <section key={bi} className="card beat-card">
            <div className="page-head">
              <strong>Beat {b.number} · {b.type}</strong>
              <button className="ghost small" disabled={busy} onClick={() => run('draft-edit', { actIndex: ai, sceneIndex: si, beatIndex: bi })}>
                {text ? 'Regenerate' : 'Write'}
              </button>
            </div>
            <p className="muted small">{b.description}{b.emotional_shift ? ` — ${b.emotional_shift}` : ''}</p>
            {text ? (
              <div className="beat-prose">
                <p>{text}</p>
                <SpeakButton text={text} />
              </div>
            ) : (
              <p className="muted small">No prose yet.</p>
            )}
          </section>
        );
      })}
    </div>
  );
}
