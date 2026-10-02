// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Cast dossiers: portrait (the story's own, else the character card's art,
// else initials), role, what drives them, their interview, their read-along
// voice. Mirrors the desktop CastSection.

import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { useStory } from '../hooks/useStory';
import type { StoryCastMember, StoryVoice } from '../storyTypes';
import { Chip, StudioShell } from './story/StudioShell';
import '../styles/ws-j.css';

function Portrait({ id, member, cardArt }: { id: string; member: StoryCastMember; cardArt?: string }) {
  const src = member.portrait
    ? `/api/stories/${id}/portrait?name=${encodeURIComponent(member.name)}`
    : cardArt;
  if (src) return <img className="s-portrait" src={src} alt="" />;
  return <div className="s-portrait">{member.name ? member.name[0] : '?'}</div>;
}

export function StoryCastPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, run, stop, save, reload } = useStory(id);
  const [painting, setPainting] = useState('');
  const [paintError, setPaintError] = useState('');
  const [voices, setVoices] = useState<StoryVoice[]>([]);
  const [art, setArt] = useState<Record<string, string>>({});
  const [open, setOpen] = useState<string | null>(null);

  useEffect(() => {
    api.get<{ voices: StoryVoice[] }>('/api/stories/voices').then((r) => setVoices(r.voices)).catch(() => {});
    api.get<{ id: string; name: string }[]>('/api/characters')
      .then((r) => setArt(Object.fromEntries(r.map((c) => [c.name, `/api/characters/${c.id}/avatar?w=128`]))))
      .catch(() => {});
  }, []);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }
  const busy = status?.running ?? false;
  const studio = p.engine_mode === 'studio';
  const pickVoice = (i: number, voiceId: string) => {
    const cast = p.cast.map((c, idx) => (idx === i ? { ...c, voice_model: voiceId || undefined } : c));
    void save({ cast });
  };
  const short = (s: string) => (s.length > 40 ? `${s.slice(0, 40)}…` : s);
  const paint = async (name: string) => {
    setPainting(name);
    setPaintError('');
    try {
      await api.post(`/api/stories/${id}/portrait`, { name });
      reload();
    } catch (e) {
      setPaintError(e instanceof ApiError ? e.message : 'Could not paint a portrait');
    } finally {
      setPainting('');
    }
  };

  return (
    <StudioShell id={id} project={p} section="cast" status={status} error={error} onStop={stop}>
      {p.cast.length === 0 && <p className="muted">No cast yet — the story bible creates it.</p>}
      {paintError && <p className="error">{paintError}</p>}
      {p.cast.map((c, i) => {
        const drive = [c.role || 'Supporting', c.desire ? `wants ${c.desire}` : '', c.flaw ? `flaw: ${c.flaw}` : ''].filter(Boolean).join(' · ');
        const interview = c.interview ?? '';
        const excerpt = interview.length > 420 ? `${interview.slice(0, 420).trimEnd()}…` : interview;
        return (
          <section key={c.name} className="s-card" style={{ marginBottom: 12 }}>
            <div className="s-row" style={{ alignItems: 'flex-start' }}>
              <Portrait id={id} member={c} cardArt={art[c.name]} />
              <div className="s-grow">
                <strong style={{ fontSize: '1rem' }}>{c.name}</strong>
                <div className="muted small">{drive}</div>
                {c.description && <div className="s-small" style={{ marginTop: 4 }}>{c.description}</div>}
              </div>
              <div className="s-row">
                {studio && (
                  <button className="s-btn-quiet" disabled={busy} onClick={() => run('interview', { name: c.name })}>
                    {interview ? 'Interview again' : `Interview ${c.name.split(' ')[0]}`}
                  </button>
                )}
                <button className="s-btn-ghost" disabled={busy || painting === c.name} onClick={() => paint(c.name)}>
                  {painting === c.name ? 'Painting…' : 'Generate portrait'}
                </button>
              </div>
            </div>
            {excerpt && (
              <>
                <span className="s-key">From their interview</span>
                <p className="s-prose" style={{ margin: 0 }}>“{open === c.name ? interview : excerpt}”</p>
                {interview.length > 420 && (
                  <button className="s-btn-ghost" style={{ alignSelf: 'flex-start' }} onClick={() => setOpen(open === c.name ? null : c.name)}>
                    {open === c.name ? 'Show less' : 'Read the whole interview'}
                  </button>
                )}
              </>
            )}
            <div className="s-chips">
              {c.voice_sample && <Chip>Voice: {short(c.voice_sample)}</Chip>}
              {c.details?.secret && <Chip tone="honey">Secret: {short(c.details.secret)}</Chip>}
            </div>
            {voices.length > 0 && (
              <label className="s-row s-small">
                <span className="muted">Read-along voice:</span>
                <select value={c.voice_model ?? ''} onChange={(e) => pickVoice(i, e.target.value)}>
                  <option value="">Default narrator</option>
                  {voices.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
                </select>
              </label>
            )}
          </section>
        );
      })}
    </StudioShell>
  );
}
