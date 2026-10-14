// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AI character creator — a stepped wizard (Mode → Details → Output → Generate
// → Greetings) mirroring the desktop creator's three modes (Quick / Guided /
// Automated). All three feed the same headless generator via POST
// /api/chargen/create; the per-mode field assembly lives in chargenForm.ts so a
// web-created card matches a desktop one. Progress streams over the WebSocket
// hub; the saved character then opens on the Greetings step (?greetings=<id>,
// so a reload keeps it), and "Open in editor" goes on to the editor.

import { useEffect, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { PersonaSeedNote, usePersonaSeed } from '../components/library/PersonaConvertDialogs';
import { api, ApiError } from '../api/client';
import { ChatSocket } from '../api/ws';
import { StepIndicator } from '../components/StepIndicator';
import { DEFAULT_FORM, buildPayload, type ChargenForm } from '../components/aichargen/chargenForm';
import { QuickConfig } from '../components/aichargen/QuickConfig';
import { GuidedConfig } from '../components/aichargen/GuidedConfig';
import { AutomatedConfig } from '../components/aichargen/AutomatedConfig';
import { OutputSettings } from '../components/aichargen/OutputSettings';
import { LoreContext } from '../components/aichargen/LoreContext';
import { GreetingsStep, type GreetingsStepHandle } from '../components/aichargen/GreetingsStep';
import { GeneratingPanel } from '../components/aichargen/GeneratingPanel';
import { ModeCards } from '../components/aichargen/ModeCards';
import { ProfileStep, type ProfileStepHandle } from '../components/aichargen/ProfileStep';
import {
  continueProfile,
  loadPending,
  stopProfile,
  viewOf,
  type ProfileView,
} from '../components/aichargen/profileApi';
import { ArrowLeft, ArrowRight, Sparkle } from '../components/aichargen/creatorIcons';
import { useUnsavedChanges } from '../hooks/useUnsavedChanges';
import '../styles/studio.css';
import '../styles/creator.css';
import '../styles/profile.css';

const STEPS = ['Mode', 'Details', 'Output', 'Generate', 'Profile', 'Greetings'];
const GENERATE = STEPS.indexOf('Generate');
const PROFILE = STEPS.indexOf('Profile');
const GREETINGS = STEPS.indexOf('Greetings');

export function CreateAiCharacterPage() {
  const navigate = useNavigate();
  const [params] = useSearchParams();
  // The character this run saved; its greetings are the last step. Held in
  // state and set with the step on chargen_done: the router applies the URL
  // as a transition, after the step change, so reading the id only from the
  // URL let one render show the step without it. The URL keeps the id across
  // a reload, and a different id arriving there is followed.
  const urlId = params.get('greetings');
  const [createdId, setCreatedId] = useState<string | null>(urlId);
  useEffect(() => {
    if (urlId) setCreatedId(urlId);
  }, [urlId]);
  const [form, setForm] = useState<ChargenForm>(DEFAULT_FORM);
  const set = (p: Partial<ChargenForm>) => setForm((f) => ({ ...f, ...p }));
  // A create pauses after the profile; the run waits on the relay (which
  // keeps it in a file), so ?profile=pending finds it again after a reload.
  // Held in state and set with the step on chargen_profile, as the id is.
  // Read once, at mount: the URL this page sets itself later is not a
  // reload to restore from.
  const [restoring, setRestoring] = useState(() => !createdId && params.get('profile') === 'pending');
  const [pending, setPending] = useState<ProfileView | null>(null);
  const [step, setStep] = useState(() => (createdId ? GREETINGS : restoring ? PROFILE : 0));
  const [writing, setWriting] = useState(false);
  const greetings = useRef<GreetingsStepHandle>(null);
  const profile = useRef<ProfileStepHandle>(null);
  const [available, setAvailable] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [steps, setSteps] = useState<string[]>([]);
  const [error, setError] = useState('');
  // "Make a Character" → AI Assist: the persona is Quick mode's brief.
  const { seed: personaSeed, error: seedError } = usePersonaSeed(params);
  const withSeed = (base: ChargenForm): ChargenForm =>
    personaSeed
      ? {
          ...base,
          mode: 'quick',
          name: personaSeed.name,
          quickConcept: personaSeed.aiConcept,
          quickScenario: '',
        }
      : base;
  useEffect(() => {
    if (!personaSeed) return;
    setForm(withSeed);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [personaSeed]);
  // Until a character exists the typed setup lives only here. After that the
  // Greetings step saves as it goes. A persona's seed is the start, not an
  // edit.
  const { prompt, leaveWithoutAsking } = useUnsavedChanges(
    !createdId && !pending && JSON.stringify(form) !== JSON.stringify(withSeed(DEFAULT_FORM)),
  );

  useEffect(() => {
    api.get<{ available: boolean }>('/api/chargen/status')
      .then((r) => setAvailable(r.available))
      .catch(() => setAvailable(false));
  }, []);

  // A reload on the Profile step: the waiting run, or the create still
  // writing it, or nothing (then the wizard starts over).
  useEffect(() => {
    if (!restoring) return;
    let alive = true;
    loadPending()
      .then(({ pending: p, creating }) => {
        setError('');
        if (!alive) return;
        if (p) {
          setPending(p);
          setStep(PROFILE);
        } else if (creating) {
          setBusy(true);
          setStep(GENERATE);
        } else {
          setStep(0);
          navigate('/create-ai', { replace: true });
        }
      })
      .catch((err) => {
        console.warn('[creator] the waiting profile could not be loaded', err);
        if (alive) setError('The profile could not be loaded. Check the connection, then try again.');
      })
      .finally(() => alive && setRestoring(false));
    return () => {
      alive = false;
    };
  }, [restoring, navigate]);

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'chargen_status' && e.data) {
        setSteps((s) => [...s, e.data!]);
      } else if (e.event === 'chargen_profile') {
        const view = viewOf(e);
        if (!view) return;
        setBusy(false);
        setCreatedId(null);
        setPending(view);
        setStep(PROFILE);
        leaveWithoutAsking();
        navigate('/create-ai?profile=pending', { replace: true });
      } else if (e.event === 'chargen_done') {
        const id = String(e.id);
        setBusy(false);
        setCreatedId(id);
        setStep(GREETINGS);
        leaveWithoutAsking();
        // Replace, so the browser's Back leaves the creator instead of
        // landing on it with no character.
        navigate(`/create-ai?greetings=${encodeURIComponent(id)}`, { replace: true });
      } else if (e.event === 'chargen_error') {
        setBusy(false);
        setError(e.error || 'Generation failed');
      } else if (e.event === 'chargen_profile_stopped' && e.phase === 'complete') {
        // Stop while the rest was written: the profile waits as it was.
        setBusy(false);
        setStep(PROFILE);
      }
    });
    socket.connect();
    return () => socket.close();
  }, [navigate, leaveWithoutAsking]);

  const generate = async () => {
    if (!form.name.trim() || busy) return;
    setBusy(true);
    // A new run replaces the one waiting on the relay.
    setPending(null);
    setSteps([]);
    setError('');
    try {
      await api.post('/api/chargen/create', {
        ...buildPayload(form),
        ...(personaSeed?.hasPortrait ? { portraitPersonaId: personaSeed.personaId } : {}),
        ...(personaSeed?.birthday ? { birthday: personaSeed.birthday } : {}),
      });
    } catch (e) {
      setBusy(false);
      setError(e instanceof ApiError ? e.message : 'Could not start generation');
    }
  };

  // Stop while the rest is written: the relay keeps the profile as it was
  // and says so (chargen_profile_stopped, phase complete).
  const stopRest = async () => {
    try {
      const r = await stopProfile();
      if (!r.stopped) {
        setBusy(false);
        setStep(PROFILE);
      }
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Stop did not reach the app. Try again.');
    }
  };

  const canAdvance =
    (step !== 0 || form.name.trim().length > 0) &&
    (step !== GENERATE || !!createdId || !!pending) &&
    (step !== PROFILE || !!createdId || !!pending);

  // Next on Profile: a pending run writes the rest (the Generate screen
  // again, then chargen_done lands on Greetings); a saved character saves
  // its profile and goes on.
  const nextFromProfile = async () => {
    const cur = profile.current?.current();
    if (!cur) return;
    setError('');
    if (createdId) {
      try {
        await continueProfile(cur.texts, cur.facts, createdId);
        setStep(GREETINGS);
      } catch (e) {
        setError(e instanceof ApiError ? e.message : 'The profile could not be saved. Try again.');
      }
      return;
    }
    setBusy(true);
    setSteps([]);
    setStep(GENERATE);
    try {
      await continueProfile(cur.texts, cur.facts);
    } catch (e) {
      setBusy(false);
      setStep(PROFILE);
      setError(e instanceof ApiError ? e.message : 'The rest could not be started. Try again.');
    }
  };
  const held = busy || writing;

  const openEditor = async () => {
    // Edits typed in the last moment go first, so the editor opens on them.
    await greetings.current?.flush();
    navigate(`/edit/${createdId}`);
  };

  return (
    <div className="page wizard studio-scope cg-scope">
      {prompt}
      <div className="cg-bar">
        <header className="page-head cg-head">
          <button type="button" className="ghost cg-library" aria-label="Library" onClick={() => navigate('/')}>
            <ArrowLeft />
            <span className="cg-library-label">Library</span>
          </button>
          <Sparkle />
          <h2>AI Character Creator</h2>
        </header>
        <StepIndicator steps={STEPS} current={step} onJump={held ? undefined : setStep} variant="porch" />
      </div>

      <div className="cg-content">
        <div className={`cg-column${step === 0 ? ' cg-column-mode' : ''}`}>
          {personaSeed && <PersonaSeedNote seed={personaSeed} />}
          {seedError && <p className="error">{seedError}</p>}

          {available === false && (
            <p className="muted">No LLM backend is ready — start or connect a model on the Models page first.</p>
          )}

          <div className="wizard-body">
            {step === 0 && (
              <div className="cg-config">
                <div className="cg-intro">
                  <h2>How do you want to create?</h2>
                  <p>Choose the creation mode that fits your workflow.</p>
                </div>
                <label className="cg-field">
                  <span className="cg-field-label">Name</span>
                  <input value={form.name} onChange={(e) => set({ name: e.target.value })} placeholder="e.g. Aria Vale" />
                </label>
                <ModeCards mode={form.mode} onPick={(mode) => set({ mode })} />
                <label className="cg-field cg-toggle">
                  <input type="checkbox" checked={form.nsfw} onChange={(e) => set({ nsfw: e.target.checked })} />
                  <span>Allow mature content</span>
                </label>
              </div>
            )}

            {step === 1 && form.mode === 'quick' && <QuickConfig form={form} set={set} />}
            {step === 1 && form.mode === 'guided' && <GuidedConfig form={form} set={set} />}
            {step === 1 && form.mode === 'automated' && <AutomatedConfig form={form} set={set} />}
            {step === 1 && <LoreContext form={form} set={set} />}

            {step === 2 && <OutputSettings form={form} set={set} />}

            {step === GENERATE && (
              <div className="cg-config">
                {busy ? (
                  // Writing: the desktop's Generate screen. Only the rest
                  // after the Profile step can be stopped.
                  <GeneratingPanel steps={steps} onStop={pending ? () => void stopRest() : undefined} />
                ) : (
                  <>
                    <div className="cg-card cg-review">
                      <div><span className="cg-review-key">Name</span><div>{form.name || '—'}</div></div>
                      <div><span className="cg-review-key">Mode</span><div style={{ textTransform: 'capitalize' }}>{form.mode}</div></div>
                      <div><span className="cg-review-key">Mature content</span><div>{form.nsfw ? 'On' : 'Off'}</div></div>
                      <div><span className="cg-review-key">Lorebook</span><div>{form.generateLorebook ? `${form.loreDepth}` : 'Off'}</div></div>
                    </div>
                    <button
                      className="primary cg-generate"
                      disabled={!form.name.trim() || available === false}
                      onClick={generate}
                    >
                      ✨ Generate character
                    </button>
                    {steps.length > 0 && (
                      <ol className="chargen-steps">
                        {steps.map((s, i) => (
                          <li key={i} className="done">{s}</li>
                        ))}
                      </ol>
                    )}
                  </>
                )}
                {error && <p className="error">{error}</p>}
              </div>
            )}

            {step === PROFILE && (createdId || pending) && (
              <ProfileStep
                key={createdId ?? 'pending'}
                ref={profile}
                initial={pending}
                characterId={createdId ?? undefined}
                onWritingChange={setWriting}
              />
            )}
            {step === PROFILE && error && (
              <p className="error">
                {error}{' '}
                {!pending && !createdId && (
                  <button type="button" className="cg-p-text-btn" onClick={() => setRestoring(true)}>
                    Try again
                  </button>
                )}
              </p>
            )}
            {step === PROFILE && !createdId && !pending && (
              <p className="muted">{restoring ? 'Loading the profile…' : 'Generate a character first; its profile opens here.'}</p>
            )}

            {step === GREETINGS && createdId && (
              <GreetingsStep
                ref={greetings}
                characterId={createdId}
                onWritingChange={setWriting}
                onOpenEditor={() => void openEditor()}
              />
            )}
            {step === GREETINGS && !createdId && (
              <p className="muted">Generate a character first; its greetings open here.</p>
            )}
          </div>
        </div>
      </div>

      <nav className="wizard-nav cg-nav" aria-label="Wizard steps">
        {step > 0 && (
          <button
            type="button"
            className="cg-back"
            disabled={step === GREETINGS ? writing : held}
            onClick={() => setStep(step - 1)}
          >
            <ArrowLeft />
            Back
          </button>
        )}
        {step === GREETINGS ? (
          <button type="button" className="cg-next" disabled={writing || !createdId} onClick={() => void openEditor()}>
            Open in editor
            <ArrowRight />
          </button>
        ) : (
          <button
            type="button"
            className="cg-next"
            disabled={!canAdvance || held}
            onClick={() => (step === PROFILE ? void nextFromProfile() : setStep(step + 1))}
          >
            Next: {STEPS[step + 1]}
            <ArrowRight />
          </button>
        )}
      </nav>
    </div>
  );
}
