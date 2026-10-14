// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Profile step on the phone: who the interview wrote, before
// anything else is built. Description, Personality and Scenario in the
// editor's boxes; a steered rewrite that streams into them (Stop keeps the
// old text); the facts the identity pass wrote, editable, re-read on demand;
// the interview, read only. The page's Next sends the texts and facts as
// they stand (`current`). A pending run comes from the page; a saved
// character (Back from Greetings) is loaded here by id.

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import { ChatSocket, type WsEvent } from '../../api/ws';
import { useLayout } from '../../hooks/useBreakpoint';
import { FactsCard } from './FactsCard';
import { ProfileFieldCard } from './ProfileFieldCard';
import { ChevronIcon, RewriteIcon, StopIcon } from './creatorIcons';
import {
  boxStates,
  factsOf,
  loadPending,
  loadSaved,
  progressOf,
  rowsFor,
  startFactsReread,
  startProfileRewrite,
  stopProfile,
  type Facts,
  type ProfileProgress,
  type ProfileTexts,
  type ProfileView,
} from './profileApi';

export type ProfileStepHandle = { current: () => { texts: ProfileTexts; facts: Facts } | null };

const STEER_PLACEHOLDER = 'What is wrong or missing? e.g. Does not follow the Tsundere personality type';

const messageOf = (err: unknown, fallback: string) =>
  err instanceof ApiError && err.message ? err.message : fallback;

export const ProfileStep = forwardRef<
  ProfileStepHandle,
  { initial: ProfileView | null; characterId?: string; onWritingChange?: (writing: boolean) => void }
>(function ProfileStep({ initial, characterId, onWritingChange }, ref) {
  const { isPhone } = useLayout();
  const [view, setView] = useState<ProfileView | null>(characterId ? null : initial);
  const [loadError, setLoadError] = useState('');
  const [steer, setSteer] = useState('');
  /** The model call running here: a rewrite (with its progress) or a re-read. */
  const [rewrite, setRewrite] = useState<ProfileProgress | null>(null);
  const [rereading, setRereading] = useState(false);
  const [error, setError] = useState('');
  const [transcriptOpen, setTranscriptOpen] = useState(false);

  const viewRef = useRef(view);
  viewRef.current = view;
  const busyRef = useRef(false);
  busyRef.current = rewrite !== null || rereading;

  useEffect(() => {
    if (!characterId) return;
    let alive = true;
    loadSaved(characterId)
      .then((v) => alive && setView(v))
      .catch(() => alive && setLoadError('This character could not be loaded. Open it from the library instead.'));
    return () => {
      alive = false;
    };
  }, [characterId]);

  useImperativeHandle(
    ref,
    () => ({
      current: () => {
        const v = viewRef.current;
        return v
          ? { texts: { description: v.description, personality: v.personality, scenario: v.scenario }, facts: v.facts }
          : null;
      },
    }),
    [],
  );
  useEffect(() => {
    onWritingChange?.(rewrite !== null || rereading);
  }, [rewrite, rereading, onWritingChange]);

  const finish = useCallback(() => {
    setRewrite(null);
    setRereading(false);
  }, []);

  useEffect(() => {
    // A phone that slept may have missed the end: ask, then take the
    // relay's texts if the call is over.
    const resync = async () => {
      if (!busyRef.current) return;
      try {
        const fresh = characterId ? await loadSaved(characterId) : (await loadPending()).pending;
        if (!fresh || fresh.writing === 'rewrite' || fresh.writing === 'facts') return;
        finish();
        if (!characterId) setView(fresh);
      } catch {
        // The next reconnect asks again.
      }
    };
    const socket = new ChatSocket((e: WsEvent) => {
      if (e.event === 'connected') {
        void resync();
        return;
      }
      if (!e.event.startsWith('chargen_profile_') && !e.event.startsWith('chargen_facts_')) return;
      if ((e.characterId ?? undefined) !== characterId) return;
      switch (e.event) {
        case 'chargen_profile_progress':
          setRewrite((r) => (r ? progressOf(e) : r));
          return;
        case 'chargen_profile_done':
          finish();
          setView(
            (v) =>
              v && {
                ...v,
                description: e.description ?? v.description,
                personality: e.personality ?? v.personality,
                scenario: e.scenario ?? v.scenario,
                facts: e.facts ? factsOf(e.facts) : v.facts,
              },
          );
          return;
        case 'chargen_facts_done':
          finish();
          setView((v) => v && { ...v, facts: factsOf(e.facts) });
          return;
        case 'chargen_profile_error':
        case 'chargen_facts_error':
          finish();
          setError(e.error || 'That did not work. Try again.');
          return;
        case 'chargen_profile_stopped':
          finish();
      }
    });
    socket.connect();
    return () => socket.close();
  }, [characterId, finish]);

  const texts = (v: ProfileView): ProfileTexts => ({
    description: v.description,
    personality: v.personality,
    scenario: v.scenario,
  });

  const startRewrite = async () => {
    const v = viewRef.current;
    if (!v || busyRef.current) return;
    setError('');
    setRewrite(progressOf({}));
    try {
      await startProfileRewrite(texts(v), steer, characterId);
    } catch (err) {
      setRewrite(null);
      setError(messageOf(err, 'The rewrite could not be started. Try again.'));
    }
  };

  const reread = async () => {
    const v = viewRef.current;
    if (!v || busyRef.current) return;
    setError('');
    setRereading(true);
    try {
      await startFactsReread(texts(v), characterId);
    } catch (err) {
      setRereading(false);
      setError(messageOf(err, 'The facts could not be read again. Try again.'));
    }
  };

  const stop = async () => {
    try {
      if ((await stopProfile(characterId)).stopped) finish();
    } catch (err) {
      setError(messageOf(err, 'Stop did not reach the app. Try again.'));
    }
  };

  if (loadError) return <p className="error">{loadError}</p>;
  if (!view) return <p className="muted">Loading the profile…</p>;

  const set = (p: Partial<ProfileView>) => setView((v) => v && { ...v, ...p });
  const states = boxStates(rewrite, view.mode);
  const writing = rewrite !== null;
  const streamed = (key: keyof ProfileTexts) =>
    rewrite && states[key] === 'writing'
      ? rewrite[key]
      : rewrite && key === 'description' && states.description === null
        ? rewrite.description || null
        : null;

  return (
    <div className="cg-greetings cg-profile" data-testid="profile-step">
      <div className="cg-g-intro">
        <h2>Profile</h2>
        <p>
          {isPhone
            ? 'Who the interview wrote. Greetings and the rest are written after Next. Edit a box, or tell the rewrite what is wrong.'
            : 'This is who the interview wrote. Read it before anything else is built: the greetings, lore, outfit and picture prompt are written after you press Next. Edit any box by hand, or tell the rewrite what is wrong.'}
        </p>
      </div>

      <ProfileFieldCard
        title="Description"
        subtitle="Who they are, as the card will carry it"
        value={view.description}
        onChange={(description) => set({ description })}
        rewriting={writing}
        state={states.description}
        streamed={streamed('description')}
      />
      <ProfileFieldCard
        title="Personality"
        subtitle="How they act and speak"
        value={view.personality}
        onChange={(personality) => set({ personality })}
        rewriting={writing}
        state={states.personality}
        streamed={streamed('personality')}
      />
      <ProfileFieldCard
        title="Scenario"
        subtitle="Where the first chat starts"
        value={view.scenario}
        onChange={(scenario) => set({ scenario })}
        rewriting={writing}
        state={states.scenario}
        streamed={null}
        scenario
      />

      <section className="cg-g-card cg-p-rewrite" aria-label="Rewrite the profile">
        <label className="cg-p-hidden-label" htmlFor="cg-profile-steer">
          What is wrong or missing
        </label>
        <textarea
          id="cg-profile-steer"
          className="cg-p-steer"
          rows={rowsFor(steer || STEER_PLACEHOLDER, isPhone ? 2 : 1)}
          placeholder={STEER_PLACEHOLDER}
          value={steer}
          disabled={writing}
          onChange={(e) => setSteer(e.target.value)}
        />
        {writing ? (
          <button type="button" className="cg-g-stop cg-p-action" onClick={() => void stop()}>
            <StopIcon />
            Stop
          </button>
        ) : (
          <button
            type="button"
            className="cg-g-regen cg-p-action"
            disabled={rereading}
            onClick={() => void startRewrite()}
          >
            <RewriteIcon />
            Rewrite the profile
          </button>
        )}
        <p className="cg-p-caption">
          {writing
            ? 'Writing a new Description, then a new Personality, then re-reading the facts below. Stop keeps the old text everywhere.'
            : isPhone
              ? 'Rewrites Description and Personality from the interview and your direction, then re-reads the facts below. A scenario you typed yourself is kept.'
              : 'Rewrites Description and Personality from the interview and your direction, then re-reads the facts below from the new profile. The box grows as you type. A scenario you typed yourself is kept.'}
        </p>
        {error && <p className="error cg-g-error">{error}</p>}
      </section>

      <FactsCard
        facts={view.facts}
        onChange={(facts) => set({ facts })}
        nsfw={view.nsfw}
        age={view.age}
        rewriting={writing}
        rereading={rereading}
        onReread={() => void reread()}
      />

      <button
        type="button"
        className={`cg-p-row${transcriptOpen ? ' open' : ''}`}
        aria-expanded={transcriptOpen}
        disabled={writing}
        onClick={() => setTranscriptOpen((o) => !o)}
      >
        <ChevronIcon open={transcriptOpen} />
        <span className="cg-p-row-title">Interview transcript</span>
        <span className="cg-p-row-note">
          {view.transcriptQuestions} questions, read only, so you can see where the rewrite came from
        </span>
      </button>
      {transcriptOpen && (
        <div className="cg-g-stream cg-p-transcript" data-testid="interview-transcript">
          {view.transcript || 'This character has no interview on record.'}
        </div>
      )}
    </div>
  );
});
