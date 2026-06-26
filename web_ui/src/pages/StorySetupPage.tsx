// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Story setup wizard: concept → style → AI config. Mirrors the desktop
// StorySetupPage; saves the full project then sends you to the bible dashboard.

import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import {
  type StoryProject,
  POV_OPTIONS, GENRES, MOODS, WRITING_STYLES, PROSE_LENGTHS,
  PACES, DIALOGUE, MATURITY, PROMPT_TIERS,
} from '../storyTypes';

const STEPS = ['Concept', 'Style', 'AI'];

export function StorySetupPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const [p, setP] = useState<StoryProject | null>(null);
  const [chars, setChars] = useState<{ id: string; name: string }[]>([]);
  const [step, setStep] = useState(0);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api.get<StoryProject>(`/api/stories/${id}`).then(setP).catch((e) =>
      setError(e instanceof ApiError ? e.message : 'Failed to load'));
    api.get<{ id: string; name: string }[]>('/api/characters')
      .then((r) => setChars(r.map((c) => ({ id: c.id, name: c.name }))))
      .catch(() => {});
  }, [id]);

  if (!p) {
    return <div className="page">{error ? <p className="error">{error}</p> : <div className="spinner" />}</div>;
  }

  const set = (patch: Partial<StoryProject>) => setP({ ...p, ...patch });
  const toggle = (key: 'selected_genres' | 'selected_moods', v: string) => {
    const cur = p[key];
    set({ [key]: cur.includes(v) ? cur.filter((x) => x !== v) : [...cur, v] } as Partial<StoryProject>);
  };
  const toggleChar = (cid: string) => {
    const cur = p.chat_history_character_ids;
    set({ chat_history_character_ids: cur.includes(cid) ? cur.filter((x) => x !== cid) : [...cur, cid] });
  };

  const finish = async () => {
    setSaving(true);
    try {
      await api.post(`/api/stories/${id}`, p);
      navigate(`/stories/${id}`);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Save failed');
      setSaving(false);
    }
  };

  const chips = (opts: string[], sel: string[], onTap: (v: string) => void) => (
    <div className="chip-select">
      {opts.map((o) => (
        <button key={o} type="button"
          className={`chip-toggle${sel.includes(o) ? ' on' : ''}`}
          onClick={() => onTap(o)}>{o}</button>
      ))}
    </div>
  );

  return (
    <div className="page wizard">
      <div className="page-head">
        <button className="ghost" onClick={() => navigate('/stories')}>← Stories</button>
        <h2>Set up your story</h2>
      </div>
      <StepIndicator steps={STEPS} current={step} onJump={setStep} />

      {step === 0 && (
        <section className="card">
          <label>Title<input value={p.title} onChange={(e) => set({ title: e.target.value })} /></label>
          <label>Concept
            <textarea rows={5} value={p.concept} onChange={(e) => set({ concept: e.target.value })}
              placeholder="The premise of your story…" />
          </label>
          <label>Themes <span className="muted small">(optional)</span>
            <input value={p.themes} onChange={(e) => set({ themes: e.target.value })}
              placeholder="redemption, found family…" />
          </label>
        </section>
      )}

      {step === 1 && (
        <section className="card">
          <label>Point of view
            <select value={p.pov} onChange={(e) => set({ pov: e.target.value })}>
              {POV_OPTIONS.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
          <label>Acts: {p.act_count}
            <input type="range" min={1} max={5} value={p.act_count}
              onChange={(e) => set({ act_count: Number(e.target.value) })} />
          </label>
          <p className="field-label">Genres</p>
          {chips(GENRES, p.selected_genres, (v) => toggle('selected_genres', v))}
          <p className="field-label">Moods</p>
          {chips(MOODS, p.selected_moods, (v) => toggle('selected_moods', v))}
          <label>Writing style
            <select value={p.writing_style} onChange={(e) => set({ writing_style: e.target.value })}>
              <option value="">Auto</option>
              {WRITING_STYLES.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
          <label>Prose length
            <select value={p.prose_length} onChange={(e) => set({ prose_length: e.target.value })}>
              {PROSE_LENGTHS.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
          <label>Narrative pace
            <select value={p.narrative_pace} onChange={(e) => set({ narrative_pace: e.target.value })}>
              {PACES.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
          <label>Dialogue density
            <select value={p.dialogue_density} onChange={(e) => set({ dialogue_density: e.target.value })}>
              {DIALOGUE.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
          <label>Maturity
            <select value={p.maturity_rating} onChange={(e) => set({ maturity_rating: e.target.value })}>
              {MATURITY.map((o) => <option key={o}>{o}</option>)}
            </select>
          </label>
        </section>
      )}

      {step === 2 && (
        <section className="card">
          <label>Model tier
            <select value={p.prompt_tier} onChange={(e) => set({ prompt_tier: e.target.value })}>
              {PROMPT_TIERS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
          </label>
          <label className="row-label">
            <input type="checkbox" checked={p.use_chat_history}
              onChange={(e) => set({ use_chat_history: e.target.checked })} />
            Seed from existing character chats
          </label>
          {p.use_chat_history && (
            <div className="char-pick">
              {chars.length === 0 ? <p className="muted small">No characters found.</p> :
                chars.map((c) => (
                  <button key={c.id} type="button"
                    className={`chip-toggle${p.chat_history_character_ids.includes(c.id) ? ' on' : ''}`}
                    onClick={() => toggleChar(c.id)}>{c.name}</button>
                ))}
            </div>
          )}
          <label className="row-label">
            <input type="checkbox" checked={p.include_user_persona}
              onChange={(e) => set({ include_user_persona: e.target.checked })} />
            Include my persona as a character
          </label>
        </section>
      )}

      {error && <p className="error">{error}</p>}
      <div className="wizard-nav">
        {step > 0 && <button className="ghost" onClick={() => setStep(step - 1)}>Back</button>}
        {step < STEPS.length - 1 ? (
          <button className="primary" onClick={() => setStep(step + 1)} disabled={!p.title.trim()}>Next</button>
        ) : (
          <button className="primary" onClick={finish} disabled={saving || !p.concept.trim()}>
            {saving ? 'Saving…' : 'Save & continue'}
          </button>
        )}
      </div>
    </div>
  );
}
