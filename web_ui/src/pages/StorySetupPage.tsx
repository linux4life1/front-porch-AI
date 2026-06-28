// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Story setup wizard: concept → style → AI config. Mirrors the desktop
// StorySetupPage; saves the full project then sends you to the bible dashboard.
// Character-card snapshots are rebuilt server-side from the selected ids + the
// role map this page sends (the web has no card text), so seeding & persona work.

import { useEffect, useRef, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import { StepIndicator } from '../components/StepIndicator';
import { OptionTiles } from './story/OptionTiles';
import {
  type StoryProject, type StoryArchetype,
  POV_OPTIONS, ROLE_OPTIONS, GENRES, MOODS, WRITING_STYLES, PROSE_LENGTHS,
  PACES, DIALOGUE, MATURITY, PROMPT_TIERS,
} from '../storyTypes';
import '../styles/ws-j.css';

const STEPS = ['Concept', 'Style', 'Cast & AI'];

export function StorySetupPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const [p, setP] = useState<StoryProject | null>(null);
  const [chars, setChars] = useState<{ id: string; name: string }[]>([]);
  const [roles, setRoles] = useState<Record<string, string>>({});
  const [archetypes, setArchetypes] = useState<StoryArchetype[]>([]);
  const [step, setStep] = useState(0);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  const rolesInit = useRef(false);

  useEffect(() => {
    api.get<StoryProject>(`/api/stories/${id}`).then(setP)
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Failed to load'));
    api.get<{ id: string; name: string }[]>('/api/characters')
      .then((r) => setChars(r.map((c) => ({ id: c.id, name: c.name }))))
      .catch(() => {});
    void rerollArchetypes();
  }, [id]);

  // Restore role assignments from existing snapshots once both the project and
  // the character list are loaded. Match by the snapshot's char `id` (web), or
  // by name (snapshots written by the desktop carry no id) — so editing a
  // desktop-made story on the web doesn't clobber its roles on save.
  useEffect(() => {
    if (!p || rolesInit.current) return;
    const charSnaps = (p.character_card_snapshots || []).filter((s) => s.self_insert !== 'true');
    if (charSnaps.length === 0) { rolesInit.current = true; return; }
    if (chars.length === 0) return; // wait for the character list
    const restored: Record<string, string> = {};
    for (const snap of charSnaps) {
      const cid = snap.id || chars.find((c) => c.name === snap.name)?.id;
      if (cid) restored[cid] = snap.role || 'Supporting';
    }
    setRoles(restored);
    rolesInit.current = true;
  }, [p, chars]);

  const rerollArchetypes = async () => {
    try {
      const r = await api.get<{ archetypes: StoryArchetype[] }>('/api/stories/archetypes');
      setArchetypes(r.archetypes);
    } catch {
      setArchetypes([]);
    }
  };

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
    const on = cur.includes(cid);
    set({ chat_history_character_ids: on ? cur.filter((x) => x !== cid) : [...cur, cid] });
    if (!on) {
      // First selected character defaults to Protagonist, like the desktop.
      const hasProtagonist = Object.values(roles).includes('Protagonist');
      setRoles({ ...roles, [cid]: hasProtagonist ? 'Supporting' : 'Protagonist' });
    }
  };

  const finish = async () => {
    setSaving(true);
    try {
      await api.post(`/api/stories/${id}`, { ...p, character_roles: roles });
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
          <p className="field-label">Quick concepts</p>
          <div className="archetype-row">
            {archetypes.map((a, i) => (
              <button key={i} type="button" className="chip-toggle"
                title={a.value} onClick={() => set({ concept: a.value })}>{a.label}</button>
            ))}
            <button type="button" className="archetype-refresh" onClick={rerollArchetypes}>↻ Refresh</button>
          </div>
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
          <OptionTiles label="Prose length" options={PROSE_LENGTHS}
            value={p.prose_length} onChange={(v) => set({ prose_length: v })} />
          <OptionTiles label="Narrative pace" options={PACES}
            value={p.narrative_pace} onChange={(v) => set({ narrative_pace: v })} />
          <OptionTiles label="Dialogue density" options={DIALOGUE}
            value={p.dialogue_density} onChange={(v) => set({ dialogue_density: v })} />
          <OptionTiles label="Maturity" options={MATURITY}
            value={p.maturity_rating} onChange={(v) => set({ maturity_rating: v })} />
        </section>
      )}

      {step === 2 && (
        <section className="card">
          <h3 className="section-label">👥 Characters &amp; sources</h3>
          <p className="muted small">
            Feature characters from your library in the story — their chat history seeds each one's
            personality, voice, and memories. You can also add your own persona as a character.
          </p>
          <label className="row-label">
            <input type="checkbox" checked={p.use_chat_history}
              onChange={(e) => set({ use_chat_history: e.target.checked })} />
            Feature characters from my library
          </label>
          {p.use_chat_history && (
            <>
              <p className="field-label">Pick characters</p>
              <div className="char-pick">
                {chars.length === 0 ? <p className="muted small">No characters found.</p> :
                  chars.map((c) => (
                    <button key={c.id} type="button"
                      className={`chip-toggle${p.chat_history_character_ids.includes(c.id) ? ' on' : ''}`}
                      onClick={() => toggleChar(c.id)}>{c.name}</button>
                  ))}
              </div>
            </>
          )}
          {p.use_chat_history && p.chat_history_character_ids.length > 0 && (
            <div style={{ marginTop: 8 }}>
              <p className="field-label">Roles</p>
              {chars.filter((c) => p.chat_history_character_ids.includes(c.id)).map((c) => (
                <div key={c.id} className="cast-role-row">
                  <span className="cast-name">{c.name}</span>
                  <select value={roles[c.id] || 'Supporting'}
                    onChange={(e) => setRoles({ ...roles, [c.id]: e.target.value })}>
                    {ROLE_OPTIONS.map((r) => <option key={r}>{r}</option>)}
                  </select>
                </div>
              ))}
            </div>
          )}
          <label className="row-label">
            <input type="checkbox" checked={p.include_user_persona}
              onChange={(e) => set({ include_user_persona: e.target.checked })} />
            Include my persona as a character
          </label>
          {p.include_user_persona && (
            <div className="persona-role">
              <span className="muted small">Persona role</span>
              <select value={p.user_persona_role || 'Protagonist'}
                onChange={(e) => set({ user_persona_role: e.target.value })}>
                {ROLE_OPTIONS.map((r) => <option key={r}>{r}</option>)}
              </select>
            </div>
          )}
          <hr style={{ border: 'none', borderTop: '1px solid var(--border)', margin: '14px 0' }} />
          <label>Model tier
            <select value={p.prompt_tier} onChange={(e) => set({ prompt_tier: e.target.value })}>
              {PROMPT_TIERS.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
            </select>
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
