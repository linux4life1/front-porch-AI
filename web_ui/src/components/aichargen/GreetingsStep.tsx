// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Greetings step on the web (#370), after Generate: the saved
// character's first message and alternates, one card each. Edit in place
// (saved once typing pauses), rewrite one (steered by a line of direction),
// add one (up to 5), delete an alternate. One greeting is written at a time;
// its card shows the text coming in and Stop, the rest wait. A greeting is
// saved by the relay only when it is done, so Stop leaves the card as it was.
// When the profile changed after these greetings were written (the relay
// compares fingerprints) a hint offers to write them all again from it or
// keep them. The example dialogue and lorebook rewrites sit at the foot, as
// this is the phone's last step. The outfit hint is desktop-only: the web
// creator has no Realism step.

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import { ChatSocket, type WsEvent } from '../../api/ws';
import { CreatorHint } from './CreatorHint';
import { GreetingCard, PlusIcon } from './GreetingCard';
import { ReviewSection, type ReviewSectionHandle } from './ReviewSection';
import { keepGreetings, rewriteAllGreetings } from './profileApi';
import {
  MAX_ALTERNATES,
  applyWritten,
  deleteAlternate,
  loadGreetings,
  saveAlternates,
  saveFirst,
  startAdd,
  startRewrite,
  stopWriting,
  withoutAlternate,
  writingStatus,
  type Greetings,
  type Writing,
} from './greetingsApi';

export type GreetingsStepHandle = { flush: () => Promise<void> };

const SAVE_PAUSE_MS = 700;

const messageOf = (err: unknown, fallback: string) =>
  err instanceof ApiError && err.message ? err.message : fallback;

const without = (errors: Record<number, string>, index: number) =>
  Object.fromEntries(Object.entries(errors).filter(([k]) => Number(k) !== index));

export const GreetingsStep = forwardRef<
  GreetingsStepHandle,
  {
    characterId: string;
    onWritingChange?: (writing: boolean) => void;
    /** The lorebook card's "Open the lorebook editor". */
    onOpenEditor?: () => void;
  }
>(function GreetingsStep({ characterId: id, onWritingChange, onOpenEditor }, ref) {
  const [g, setG] = useState<Greetings | null>(null);
  const [loadError, setLoadError] = useState('');
  const [steers, setSteers] = useState<string[]>([]);
  const [writing, setWriting] = useState<Writing | null>(null);
  const [errors, setErrors] = useState<Record<number, string>>({});
  const [saveError, setSaveError] = useState('');
  /** The profile changed after these greetings were written (the relay
   *  compares fingerprints), and "Rewrite the greetings from it" running. */
  const [changed, setChanged] = useState(false);
  const [rewritingAll, setRewritingAll] = useState(false);
  const [hintError, setHintError] = useState('');
  const [reviewWriting, setReviewWriting] = useState(false);

  // The latest of each, for saves and socket events that outlive a render.
  const gRef = useRef<Greetings | null>(null);
  gRef.current = g;
  const writingRef = useRef<Writing | null>(null);
  writingRef.current = writing;
  /** The last index a rewrite-all writes, while it runs. */
  const allRef = useRef<number | null>(null);
  const review = useRef<ReviewSectionHandle>(null);
  const dirty = useRef({ first: false, alts: false });
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    let alive = true;
    setG(null);
    setLoadError('');
    loadGreetings(id)
      .then((v) => {
        if (!alive) return;
        setG(v);
        setSteers(Array<string>(v.alts.length + 1).fill(''));
      })
      .catch(() => {
        if (alive) setLoadError('This character could not be loaded. Open it from the library instead.');
      });
    writingStatus(id)
      .then((s) => alive && setChanged(s.profileChanged === true))
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [id]);

  /** Save what was typed. The alternates wait while one of them is written:
   *  the relay puts that one into the card as it is then, these follow. */
  const flush = useCallback(async () => {
    window.clearTimeout(timer.current);
    const cur = gRef.current;
    if (!cur) return;
    const saves: Promise<unknown>[] = [];
    if (dirty.current.first) {
      dirty.current.first = false;
      saves.push(saveFirst(id, cur.first));
    }
    const altWriting = (writingRef.current?.index ?? 0) >= 1;
    if (dirty.current.alts && !altWriting) {
      dirty.current.alts = false;
      saves.push(saveAlternates(id, cur));
    }
    try {
      await Promise.all(saves);
      setSaveError('');
    } catch (err) {
      setSaveError(messageOf(err, 'Your edit could not be saved. Check the connection, then type again.'));
    }
  }, [id]);

  useImperativeHandle(ref, () => ({ flush }), [flush]);
  // Leaving the step keeps what was typed in the last moment.
  useEffect(() => () => void flush(), [flush]);
  useEffect(() => {
    onWritingChange?.(writing !== null || rewritingAll || reviewWriting);
  }, [writing, rewritingAll, reviewWriting, onWritingChange]);
  // Edits held while an alternate was written go out once it is done.
  useEffect(() => {
    if (!writing && dirty.current.alts) void flush();
  }, [writing, flush]);

  const scheduleSave = (part: 'first' | 'alts') => {
    dirty.current[part] = true;
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => void flush(), SAVE_PAUSE_MS);
  };

  /** A rewrite-all is over; [rewritten] when it wrote every greeting. */
  const endAll = useCallback((rewritten: boolean) => {
    if (allRef.current === null) return;
    allRef.current = null;
    setRewritingAll(false);
    if (rewritten) setChanged(false);
  }, []);

  const finish = useCallback((index: number, text: string | null, error?: string) => {
    const w = writingRef.current;
    if (!w || w.index !== index) return;
    writingRef.current = null;
    setWriting(null);
    if (text !== null) {
      if (index > (gRef.current?.alts.length ?? 0)) setSteers((s) => [...s, '']);
      setG((cur) => cur && applyWritten(cur, index, text));
    }
    if (error) setErrors((e) => ({ ...e, [index]: error }));
  }, []);

  useEffect(() => {
    // A phone that slept may have missed the end of a write: ask, then read
    // the saved card if it is over.
    const resync = async () => {
      const w = writingRef.current;
      if (!w) return;
      try {
        if ((await writingStatus(id)).writing === w.index) return;
        const fresh = await loadGreetings(id);
        finish(w.index, (w.index === 0 ? fresh.first : fresh.alts[w.index - 1]) ?? null);
      } catch {
        // The next reconnect asks again.
      }
    };
    const socket = new ChatSocket((e: WsEvent) => {
      if (e.event === 'connected') {
        void resync();
        review.current?.onEvent(e);
        return;
      }
      if (e.event.startsWith('chargen_rewrite_')) {
        review.current?.onEvent(e);
        return;
      }
      if (!e.event.startsWith('chargen_greeting') || String(e.characterId ?? '') !== id) return;
      const index = typeof e.index === 'number' ? e.index : -1;
      if (e.event === 'chargen_greeting_progress') {
        setWriting((w) => (w && w.index === index ? { index, text: e.text ?? '' } : w));
      } else if (e.event === 'chargen_greeting_done') {
        finish(index, e.text ?? '');
        // A rewrite-all goes on to the next greeting by itself.
        const last = allRef.current;
        if (last !== null && index < last) {
          const next = { index: index + 1, text: '' };
          writingRef.current = next;
          setWriting(next);
        }
      } else if (e.event === 'chargen_greeting_error') {
        finish(index, null, e.error || 'The greeting could not be written.');
        endAll(false);
      } else if (e.event === 'chargen_greeting_stopped') {
        finish(index, null);
        endAll(false);
      } else if (e.event === 'chargen_greetings_rewritten') {
        endAll(true);
      }
    });
    socket.connect();
    return () => socket.close();
  }, [id, finish, endAll]);

  const begin = async (index: number, start: () => Promise<unknown>) => {
    if (writingRef.current || !gRef.current) return;
    await flush();
    setErrors((e) => without(e, index));
    const w = { index, text: '' };
    // Set now: a fast model's done event can beat the next render.
    writingRef.current = w;
    setWriting(w);
    try {
      await start();
    } catch (err) {
      if (writingRef.current === w) {
        writingRef.current = null;
        setWriting(null);
      }
      setErrors((e) => ({ ...e, [index]: messageOf(err, 'The greeting could not be started. Try again.') }));
    }
  };

  const remove = async (index: number) => {
    if (writingRef.current) return;
    await flush();
    try {
      await deleteAlternate(id, index);
      setG((cur) => cur && withoutAlternate(cur, index));
      setSteers((s) => s.filter((_, i) => i !== index));
      setErrors({});
    } catch (err) {
      setErrors((e) => ({ ...e, [index]: messageOf(err, 'The greeting could not be deleted. Try again.') }));
    }
  };

  const stop = async () => {
    const w = writingRef.current;
    if (!w) return;
    try {
      // false: it had already ended, and its done or error event says how.
      if ((await stopWriting(id)).stopped) finish(w.index, null);
    } catch (err) {
      setErrors((e) => ({ ...e, [w.index]: messageOf(err, 'Stop did not reach the app. Try again.') }));
    }
  };

  const rewriteAll = async () => {
    const cur = gRef.current;
    if (writingRef.current || !cur) return;
    await flush();
    setHintError('');
    allRef.current = cur.alts.length;
    setRewritingAll(true);
    const first = { index: 0, text: '' };
    writingRef.current = first;
    setWriting(first);
    try {
      await rewriteAllGreetings(id);
    } catch (err) {
      allRef.current = null;
      setRewritingAll(false);
      writingRef.current = null;
      setWriting(null);
      setHintError(messageOf(err, 'The greetings could not be rewritten. Try again.'));
    }
  };

  const keep = async () => {
    setHintError('');
    try {
      await keepGreetings(id);
      setChanged(false);
    } catch (err) {
      setHintError(messageOf(err, 'That did not reach the app. Try again.'));
    }
  };

  if (loadError) return <p className="error">{loadError}</p>;
  if (!g) return <p className="muted">Loading the greetings…</p>;

  const busy = writing !== null || rewritingAll || reviewWriting;
  const addIndex = g.alts.length + 1;
  const adding = writing?.index === addIndex;
  const card = (index: number, value: string | null) => (
    <GreetingCard
      key={index}
      index={index}
      title={index === 0 ? 'First message' : `Alternate ${index}`}
      subtitle={index === 0 ? 'Opens every new chat' : undefined}
      value={value}
      onChange={(v) => {
        if (index === 0) {
          setG((cur) => cur && { ...cur, first: v });
          scheduleSave('first');
        } else {
          setG((cur) => cur && { ...cur, alts: cur.alts.map((a, j) => (j === index - 1 ? v : a)) });
          scheduleSave('alts');
        }
      }}
      steer={steers[index] ?? ''}
      onSteer={(v) => setSteers((s) => s.map((x, i) => (i === index ? v : x)))}
      writing={writing?.index === index ? writing.text : null}
      locked={busy && writing?.index !== index}
      error={errors[index]}
      onRegenerate={() => void begin(index, () => startRewrite(id, index, steers[index] ?? ''))}
      onStop={() => void stop()}
      onDelete={index === 0 ? undefined : () => void remove(index)}
    />
  );

  return (
    <div className="cg-greetings" data-testid="greetings-step">
      <div className="cg-g-intro">
        <h2>Greetings</h2>
        <p>
          <span className="cg-g-wide">
            The first message opens every new chat. Alternates are other openings you can swipe to.{' '}
          </span>
          Edit any of them, rewrite one, or steer a rewrite with a line of direction.
        </p>
      </div>
      {changed && !rewritingAll && (
        <CreatorHint
          title="The profile changed"
          body="These greetings were written from the old Description and Personality. Nothing was changed for you."
          action="Rewrite the greetings from it"
          onAction={() => void rewriteAll()}
          dismiss="Keep them"
          onDismiss={() => void keep()}
          disabled={busy}
        />
      )}
      {hintError && <p className="error">{hintError}</p>}
      {card(0, g.first)}
      <div className="cg-g-alt-head">
        <h2>Alternate greetings</h2>
        <span data-testid="greeting-count">
          {g.alts.length} of {MAX_ALTERNATES}
        </span>
      </div>
      {g.alts.map((a, i) => card(i + 1, a))}
      {adding && card(addIndex, null)}
      {!adding && errors[addIndex] && <p className="error">{errors[addIndex]}</p>}
      <div className="cg-g-add">
        <button
          type="button"
          className="cg-g-add-btn"
          title="Writes a new one right away"
          disabled={busy || g.alts.length >= MAX_ALTERNATES}
          onClick={() => void begin(addIndex, () => startAdd(id))}
        >
          <PlusIcon />
          Add another greeting
        </button>
        <span className="cg-g-hint">Writes a new one right away</span>
      </div>
      {saveError && <p className="error">{saveError}</p>}
      <ReviewSection
        ref={review}
        characterId={id}
        locked={writing !== null || rewritingAll}
        onWritingChange={setReviewWriting}
        onOpenEditor={onOpenEditor}
      />
    </div>
  );
});
