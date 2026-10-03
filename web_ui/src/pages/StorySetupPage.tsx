// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// New Story: Idea → Cast → Shape → Engine, with a summary rail that fills in
// as you go. The project row is created on the first Next and saved after
// every step, so backing out keeps the draft and the shelf shows where it
// stopped. At /stories/:id/setup it reopens an existing story's setup (the
// studio's "Setup" button). Web twin of lib/ui/pages/story_setup_page.dart.

import { useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate, useParams } from 'react-router-dom';
import { api, ApiError } from '../api/client';
import type { StoryProject } from '../storyTypes';
import { CastStep } from './story/setup/CastStep';
import {
  adoptChat, applyDraft, draftFromProject, emptyDraft,
  type CharacterRow, type ChatSource, type Draft,
} from './story/setup/draft';
import { EngineStep } from './story/setup/EngineStep';
import { IdeaStep } from './story/setup/IdeaStep';
import { useNarrow } from './story/setup/primitives';
import { SetupRail } from './story/setup/SetupRail';
import { ShapeStep } from './story/setup/ShapeStep';
import { useLaneLabels } from './story/setup/useLaneLabels';
import { loadCharacters, loadPersonaName } from './story/setup/useSetupData';
import '../styles/studio.css';

const STEPS = ['Idea', 'Cast', 'Shape', 'Engine'];

const message = (e: unknown, fallback: string) => (e instanceof ApiError ? e.message : fallback);

export function StorySetupPage() {
  const { id: routeId } = useParams();
  const navigate = useNavigate();
  const location = useLocation();
  const fromChat = (location.state as { fromChat?: ChatSource } | null)?.fromChat;
  const narrow = useNarrow();

  const [loaded, setLoaded] = useState(false);
  const [draft, setDraft] = useState<Draft>(emptyDraft);
  const [chars, setChars] = useState<CharacterRow[]>([]);
  const [personaName, setPersonaName] = useState('User');
  const [step, setStep] = useState(0);
  const [reached, setReached] = useState(0);
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');
  // The project as last saved: the base every save writes the draft onto.
  const project = useRef<StoryProject | null>(null);
  const busy = useRef(false);
  const root = useRef<HTMLDivElement | null>(null);
  const laneLabels = useLaneLabels(draft.lanes);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const [characters, persona, existing] = await Promise.all([
          loadCharacters().catch(() => [] as CharacterRow[]),
          loadPersonaName(),
          routeId ? api.get<StoryProject>(`/api/stories/${routeId}`) : Promise.resolve(null),
        ]);
        if (!live) return;
        let next = existing ? draftFromProject(existing, characters) : emptyDraft();
        let start = 0;
        if (existing) {
          project.current = existing;
          // Finished = the wizard cleared its step (null); a draft keeps the step it stopped at.
          const done = existing.setup_step == null && !!existing.concept?.trim();
          setEditing(done);
          // A draft resumes where it stopped; a finished story reopens every step.
          if (typeof existing.setup_step === 'number') start = Math.min(Math.max(existing.setup_step, 0), STEPS.length - 1);
          setReached(done ? STEPS.length - 1 : start);
        }
        if (fromChat) next = adoptChat(next, fromChat, persona);
        setChars(characters);
        setPersonaName(persona);
        setDraft(next);
        setStep(start);
        setLoaded(true);
      } catch (e) {
        if (live) setError(message(e, 'Could not open this story.'));
      }
    })();
    return () => { live = false; };
  }, [routeId, fromChat]);

  // Phones get a fifth "Ready?" screen in place of the rail.
  const stepCount = STEPS.length + (narrow ? 1 : 0);
  const at = Math.min(step, stepCount - 1);
  const last = at === stepCount - 1;
  const label = at < STEPS.length ? STEPS[at] : 'Ready?';

  useEffect(() => { root.current?.scrollIntoView({ block: 'start' }); }, [at]);

  /** Create the row on the first save; write the draft onto it. `setupStep` is where a resume starts (null once built). */
  const save = async (setupStep: number | null): Promise<boolean> => {
    if (busy.current) return false;
    busy.current = true;
    setSaving(true);
    setError('');
    try {
      let base = project.current;
      if (!base) {
        const created = await api.post<{ id: string }>('/api/stories', { title: draft.title.trim() });
        base = await api.get<StoryProject>(`/api/stories/${created.id}`);
        project.current = base;
      }
      const next = applyDraft(base, draft, chars, personaName);
      if (!editing) next.setup_step = setupStep;
      await api.post(`/api/stories/${next.id}`, next);
      project.current = next;
      return true;
    } catch (e) {
      setError(message(e, 'Could not save. Check that the app is running, then try again.'));
      return false;
    } finally {
      busy.current = false;
      setSaving(false);
    }
  };

  const leave = () => {
    if (location.key === 'default') navigate('/stories');
    else navigate(-1);
  };

  /** Nothing saved yet: nothing to keep. Otherwise keep the draft where it stopped. */
  const close = async () => {
    if (project.current && !(await save(at))) return;
    leave();
  };

  const back = async () => {
    if (project.current) await save(at - 1);
    setStep(at - 1);
  };

  const finish = async () => {
    if (!(await save(null))) return;
    if (editing) {
      leave();
      return;
    }
    const id = project.current?.id;
    try {
      await api.post(`/api/stories/${id}/run`, { stage: 'story-architect' });
    } catch (e) {
      setError(message(e, 'Saved, but the bible could not start. Press the button again to retry.'));
      return;
    }
    navigate(`/stories/${id}`, { replace: true });
  };

  const next = async () => {
    if (at === 0 && !draft.concept.trim()) {
      setNotice('Say what the story is first.');
      return;
    }
    setNotice('');
    if (!last) {
      if (!(await save(at + 1))) return;
      setStep(at + 1);
      setReached((r) => Math.max(r, at + 1));
      return;
    }
    await finish();
  };

  if (!loaded) {
    return (
      <div className="studio-scope wiz">
        {error ? <p className="s-error" style={{ padding: 16 }}>{error}</p> : <div className="spinner" aria-label="Loading" />}
      </div>
    );
  }

  const nextLabel = last
    ? (editing ? 'Save changes' : 'Build the story bible')
    : `Next: ${STEPS[at + 1] ?? 'Ready?'}`;
  const shared = { draft, set: setDraft };
  const rail = { draft, step: at, chars, personaName, laneLabels };

  return (
    <div className="studio-scope wiz" ref={root} data-testid="story-setup">
      <header className="wiz-head">
        <button type="button" className="s-btn-ico ghost" aria-label="Back to stories" onClick={() => void close()}>←</button>
        <span className="t">{editing ? 'Setup' : 'New story'}</span>
        <span className="s" data-testid="story-setup-step">{label}</span>
        <span className="s-spacer" />
        <div className="s-steps" role="group" aria-label="Steps">
          {STEPS.map((name, i) => (
            <button key={name} type="button" data-testid={`story-step-${i}`}
              className={i < at ? 'done' : i === at ? 'on' : ''} aria-current={i === at ? 'step' : undefined}
              disabled={i > reached} onClick={() => setStep(i)}>
              <i>{i < at ? '✓' : i + 1}</i>{name}
            </button>
          ))}
        </div>
      </header>

      <div className="wiz-body">
        <div className="wiz-main">
          <div className="wiz-inner" key={at}>
            {at === 0 && <IdeaStep {...shared} chars={chars} userName={personaName} />}
            {at === 1 && <CastStep {...shared} chars={chars} personaName={personaName} />}
            {at === 2 && <ShapeStep {...shared} />}
            {at === 3 && <EngineStep {...shared} laneLabels={laneLabels} />}
            {at >= STEPS.length && <SetupRail {...rail} asPage />}
            {notice && <span className="s-muted" role="status">{notice}</span>}
            {error && <span className="s-error" role="alert">{error}</span>}
          </div>
        </div>
        {!narrow && <SetupRail {...rail} />}
      </div>

      <footer className="wiz-foot">
        <button type="button" className="s-btn-ghost" data-testid="story-setup-back"
          onClick={() => void (at === 0 ? close() : back())}>{at === 0 ? 'Cancel' : 'Back'}</button>
        <span className="s-spacer" />
        {narrow && <span className="s-muted s-small">{at + 1} of {stepCount}</span>}
        <button type="button" className="s-btn-primary" data-testid="story-setup-next" disabled={saving} onClick={() => void next()}>
          {nextLabel}
        </button>
      </footer>
    </div>
  );
}
