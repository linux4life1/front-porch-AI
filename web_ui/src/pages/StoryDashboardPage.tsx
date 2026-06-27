// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Story bible dashboard: view the generated structure (concept, cast + voices,
// threads, lore, editable acts + convergence points), distill chat history, drive
// the pipeline with live progress, export (txt/md/epub/audiobook), and jump to
// the structure/writer/reader. Mirrors the desktop StoryDashboardPage.

import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { StoryAct, StoryVoice } from '../storyTypes';
import { ChatDistillPanel } from './story/ChatDistillPanel';
import { CastVoiceEditor } from './story/CastVoiceEditor';
import { ActsEditor } from './story/ActsEditor';
import { StoryExportBar } from './story/StoryExportBar';
import '../styles/ws-j.css';

export function StoryDashboardPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const { project: p, status, error, run, save } = useStory(id);
  const [voices, setVoices] = useState<StoryVoice[]>([]);

  useEffect(() => {
    api.get<{ voices: StoryVoice[] }>('/api/stories/voices')
      .then((r) => setVoices(r.voices)).catch(() => {});
  }, []);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  const busy = status?.running ?? false;
  const hasBible = p.concept.trim() !== '' && (p.cast.length > 0 || p.status_quo.trim() !== '');
  const hasActs = p.acts.length > 0;
  const hasProse = !!p.prose && Object.keys(p.prose).length > 0;

  const pickVoice = (i: number, voiceId: string) => {
    const cast = p.cast.map((c, idx) =>
      idx === i ? { ...c, voice_model: voiceId || undefined } : c);
    void save({ cast });
  };
  const saveActs = async (acts: StoryAct[]) => { await save({ acts }); };

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
            {hasProse && (
              <button className="ghost" onClick={() => navigate(`/stories/${id}/read`)}>Read 📖</button>
            )}
          </div>
        )}
      </section>

      {p.use_chat_history && (
        <ChatDistillPanel id={id} project={p} busy={busy} onRedistill={() => run('chat-distiller')} />
      )}

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
            <CastVoiceEditor cast={p.cast} voices={voices} onPick={pickVoice} />
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

          {hasActs && <ActsEditor project={p} busy={busy} onSave={saveActs} />}

          <StoryExportBar id={id} title={p.title} />
        </>
      )}
    </div>
  );
}
