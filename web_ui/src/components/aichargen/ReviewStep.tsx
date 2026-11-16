// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AI creator's Review step (desktop review_step.dart): the portrait rail
// (AvatarRail) on the left, the card's name and tags under it, and the
// editable review on the right — Description, Personality, Scenario, First
// Message, each alternate greeting with its opening-state form, the example
// dialogue rewrite, the System Prompt, and the lorebook with keep boxes and
// per-entry editing. It saves as you type; Save & Finish flushes and applies
// the lorebook keep list. The two rewrites stream over one socket owned here.

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import { ChatSocket } from '../../api/ws';
import { GreetingSeedForm } from '../GreetingSeedForm';
import { usePassageOfTime } from '../realism/usePassageOfTime';
import type { LoreEntry } from '../LoreEntriesEditor';
import type { GreetingSeed } from '../realism/realismTypes';
import { AvatarRail } from './AvatarRail';
import { ReviewDialogueCard } from './ReviewDialogueCard';
import { ReviewLorebookCard } from './ReviewLorebookCard';
import { ReviewLoreEntryModal } from './ReviewLoreEntryModal';
import { ReviewTextCard } from './ReviewTextCard';
import {
  dialogueSubtitle,
  loadReview,
  startReviewRewrite,
  stopReviewRewrite,
  type Review,
} from './profileApi';
import { loadReviewDetail, saveFields, type ReviewDetail } from './reviewApi';

export type ReviewStepHandle = { flush: () => Promise<void> };

type Field = 'mesExample' | 'lorebook';
type TextKey = 'description' | 'personality' | 'scenario' | 'firstMessage' | 'systemPrompt';

const SAVE_PAUSE_MS = 700;

const TEXT_CARDS: { key: TextKey; title: string; subtitle?: string; rows: number }[] = [
  { key: 'description', title: 'Description', subtitle: 'Who they are, as the card will carry it', rows: 6 },
  { key: 'personality', title: 'Personality', subtitle: 'How they act and speak', rows: 4 },
  { key: 'scenario', title: 'Scenario', subtitle: 'Where the first chat starts', rows: 3 },
  { key: 'firstMessage', title: 'First Message', subtitle: 'Opens every new chat', rows: 6 },
];

const messageOf = (err: unknown, fallback: string) =>
  err instanceof ApiError && err.message ? err.message : fallback;

export const ReviewStep = forwardRef<
  ReviewStepHandle,
  {
    characterId: string;
    /** True while a rewrite, a pending save or a rail action runs: the
     *  wizard's Back and Save & Finish wait for it. */
    onWritingChange?: (writing: boolean) => void;
  }
>(function ReviewStep({ characterId: id, onWritingChange }, ref) {
  const [detail, setDetail] = useState<ReviewDetail | null>(null);
  const [review, setReview] = useState<Review | null>(null);
  const [writing, setWriting] = useState<{ field: Field; text: string } | null>(null);
  const [errors, setErrors] = useState<Partial<Record<Field, string>>>({});
  const [loadError, setLoadError] = useState('');
  const [saveError, setSaveError] = useState('');
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [railBusy, setRailBusy] = useState(false);
  const [kept, setKept] = useState<boolean[]>([]);
  const [loreOpen, setLoreOpen] = useState(false);
  const [editingLore, setEditingLore] = useState<number | null>(null);
  const clockOn = usePassageOfTime();

  const detailRef = useRef(detail);
  detailRef.current = detail;
  const reviewRef = useRef(review);
  reviewRef.current = review;
  const keptRef = useRef(kept);
  keptRef.current = kept;
  const writingRef = useRef(writing);
  writingRef.current = writing;
  const dirtyRef = useRef(dirty);
  dirtyRef.current = dirty;

  const pending = useRef<Record<string, unknown>>({});
  const loreDirty = useRef(false);
  const timers = useRef<Record<string, number>>({});
  const saveChain = useRef<Promise<void>>(Promise.resolve());

  const refresh = useCallback(async (resetKeep = false) => {
    try {
      const [d, r] = await Promise.all([loadReviewDetail(id), loadReview(id)]);
      setDetail(d);
      setReview(r);
      if (resetKeep) {
        // The rewrite replaced the entries; the old checkboxes were about the
        // old content. Every new entry starts kept, and the host already
        // persisted the rewrite, so there is nothing to post.
        const all = Array<boolean>(d.lorebook.length).fill(true);
        keptRef.current = all;
        setKept(all);
        loreDirty.current = false;
        setDirty(Object.keys(pending.current).length > 0);
      } else {
        setKept((cur) =>
          cur.length === d.lorebook.length ? cur : Array<boolean>(d.lorebook.length).fill(true),
        );
      }
      setLoadError('');
      const w: Field | null = r.writing === 'mesExample' || r.writing === 'lorebook' ? r.writing : null;
      const next = (cur: { field: Field; text: string } | null) =>
        w ? (cur?.field === w ? cur : { field: w, text: '' }) : null;
      writingRef.current = next(writingRef.current);
      setWriting(next);
    } catch (err) {
      console.warn('[creator] the review could not be loaded', err);
      setLoadError('The review could not be loaded. Check the connection, then try again.');
    }
  }, [id]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    onWritingChange?.(writing !== null || dirty || saving || railBusy);
  }, [writing, dirty, saving, railBusy, onWritingChange]);

  useEffect(() => () => {
    for (const t of Object.values(timers.current)) window.clearTimeout(t);
  }, []);

  const saveNow = useCallback(async () => {
    const payload = { ...pending.current };
    const lore =
      loreDirty.current && detailRef.current
        ? detailRef.current.lorebook.filter((_, i) => keptRef.current[i] !== false)
        : null;
    if (Object.keys(payload).length === 0 && lore === null) {
      setDirty(false);
      return;
    }
    setSaving(true);
    try {
      await saveFields(id, lore === null ? payload : { ...payload, lorebook: lore });
      for (const [key, value] of Object.entries(payload)) {
        if (pending.current[key] === value) delete pending.current[key];
      }
      if (lore !== null) loreDirty.current = false;
      setSaveError('');
      setDirty(Object.keys(pending.current).length > 0 || loreDirty.current);
    } catch (err) {
      setSaveError(messageOf(err, 'Your edit could not be saved. Try again.'));
      setDirty(true);
      throw err;
    } finally {
      setSaving(false);
    }
  }, [id]);

  const enqueueSave = useCallback(() => {
    // Every save goes through one chain: a debounced save and Save & Finish
    // can never race, so the server keeps the last value the person saw.
    const run = saveChain.current.then(() => saveNow());
    saveChain.current = run.catch(() => {});
    return run;
  }, [saveNow]);

  const flush = useCallback(async () => {
    for (const t of Object.values(timers.current)) window.clearTimeout(t);
    timers.current = {};
    await enqueueSave();
  }, [enqueueSave]);

  const editField = (key: string, value: unknown) => {
    pending.current[key] = value;
    setDirty(true);
    window.clearTimeout(timers.current[key]);
    timers.current[key] = window.setTimeout(() => {
      void enqueueSave().catch(() => {});
    }, SAVE_PAUSE_MS);
  };

  const editText = (key: TextKey, value: string) => {
    setDetail((d) => (d ? { ...d, [key]: value } : d));
    editField(key, value);
  };

  const editAlt = (index: number, value: string) => {
    const cur = detailRef.current;
    if (!cur) return;
    const alts = [...cur.alternateGreetings];
    alts[index] = value;
    setDetail({ ...cur, alternateGreetings: alts });
    editField('alternateGreetings', alts);
    editField('greetingSeeds', cur.seeds);
  };

  const editSeed = (index: number, seed: GreetingSeed | null) => {
    const cur = detailRef.current;
    if (!cur) return;
    const seeds = [...cur.seeds];
    seeds[index] = seed;
    setDetail({ ...cur, seeds });
    editField('greetingSeeds', seeds);
    editField('alternateGreetings', cur.alternateGreetings);
  };

  const editDialogue = (text: string) => {
    setReview((r) => r && { ...r, mesExample: text });
    editField('mesExample', text);
  };

  const start = async (field: Field, direction: string) => {
    if (writingRef.current) return;
    try {
      await flush();
    } catch {
      return;
    }
    setErrors((x) => ({ ...x, [field]: undefined }));
    const w = { field, text: '' };
    writingRef.current = w;
    setWriting(w);
    try {
      await startReviewRewrite(id, field, direction);
    } catch (err) {
      if (writingRef.current === w) {
        writingRef.current = null;
        setWriting(null);
      }
      setErrors((x) => ({ ...x, [field]: messageOf(err, 'The rewrite could not be started. Try again.') }));
    }
  };

  const stop = async () => {
    const field = writingRef.current?.field ?? 'mesExample';
    try {
      const r = await stopReviewRewrite(id);
      if (r.stopped) {
        writingRef.current = null;
        setWriting(null);
        return;
      }
      // Nothing to stop means the end was missed: read what happened.
      await refresh(field === 'lorebook');
      writingRef.current = null;
      setWriting(null);
    } catch (err) {
      setErrors((x) => ({ ...x, [field]: messageOf(err, 'Stop did not reach the app. Try again.') }));
    }
  };

  useEffect(() => {
    const socket = new ChatSocket((e) => {
      if (e.event === 'connected') {
        if (!dirtyRef.current) void refresh();
        return;
      }
      if (!e.event.startsWith('chargen_rewrite_')) return;
      if (String(e.characterId ?? '') !== id) return;
      const field: Field = e.field === 'lorebook' ? 'lorebook' : 'mesExample';
      if (e.event === 'chargen_rewrite_progress') {
        setWriting((w) => (w && w.field === field ? { field, text: e.text ?? '' } : w));
        return;
      }
      // Only the card being written ends here; a late event for the other one
      // must not clear it while the relay still writes.
      const active = writingRef.current;
      if (active && active.field !== field) return;
      if (active) {
        writingRef.current = null;
        setWriting(null);
      }
      if (e.event === 'chargen_rewrite_done') {
        if (field === 'lorebook') {
          void refresh(true);
        } else {
          setReview((r) => r && { ...r, mesExample: e.text ?? '' });
        }
      } else if (e.event === 'chargen_rewrite_error' && active) {
        setErrors((x) => ({ ...x, [field]: e.error || 'The rewrite failed.' }));
      }
    });
    socket.connect();
    return () => socket.close();
  }, [id, refresh]);

  useImperativeHandle(ref, () => ({ flush }), [flush]);

  const toggleKeep = (index: number, keep: boolean) => {
    setKept((cur) => {
      const next = [...cur];
      next[index] = keep;
      return next;
    });
    loreDirty.current = true;
    setDirty(true);
  };

  const saveLore = (index: number, entry: LoreEntry) => {
    setDetail((d) => {
      if (!d) return d;
      const lorebook = [...d.lorebook];
      lorebook[index] = entry;
      return { ...d, lorebook };
    });
    loreDirty.current = true;
    setDirty(true);
    setEditingLore(null);
  };

  if (!detail || !review) {
    return loadError ? (
      <p className="error" data-testid="review-load-error">
        {loadError}{' '}
        <button type="button" className="cg-p-text-btn" onClick={() => void refresh()}>
          Try again
        </button>
      </p>
    ) : (
      <p className="muted">Loading the review…</p>
    );
  }

  const busy = writing !== null;
  const handEdited = review.lorebook.map((r) => r.handEdited);
  const loreEditing =
    editingLore !== null && detail.lorebook[editingLore] ? editingLore : null;

  return (
    <div className="cg-r-layout">
      <aside className="cg-r-rail">
        <AvatarRail
          characterId={id}
          seed={review.portraitPromptSeed}
          description={detail.description}
          onBusyChange={setRailBusy}
        />
        <h2 className="cg-r-name">{detail.name}</h2>
        {detail.tags.length > 0 && (
          <div className="cg-r-tags" aria-label="Tags">
            {detail.tags.map((tag) => (
              <span className="cg-r-tag" key={tag}>
                {tag}
              </span>
            ))}
          </div>
        )}
      </aside>

      <div className="cg-r-main">
        <h2 className="cg-r-title">Review</h2>
        <p className="cg-r-intro">
          Everything the creator wrote, in one place. The profile and greetings are above. Example
          dialogue and the lorebook take the same line of direction as the rest.
        </p>
        {saveError && <p className="error">{saveError}</p>}
        <div className="cg-r-cards">
          {TEXT_CARDS.map((card) => (
            <ReviewTextCard
              key={card.key}
              title={card.title}
              subtitle={card.subtitle}
              value={detail[card.key]}
              rows={card.rows}
              onChange={(v) => editText(card.key, v)}
            />
          ))}
          {detail.alternateGreetings.map((greeting, i) => (
            <ReviewTextCard
              key={`alt-${i}`}
              title={`Alternate greeting ${i + 1}`}
              value={greeting}
              rows={4}
              onChange={(v) => editAlt(i, v)}
              below={
                <GreetingSeedForm
                  seed={detail.seeds[i] ?? null}
                  showNeeds
                  showInventory
                  clockOn={clockOn}
                  onChange={(seed) => editSeed(i, seed)}
                />
              }
            />
          ))}
          <ReviewDialogueCard
            value={review.mesExample}
            subtitle={dialogueSubtitle(review.sex, review.hadInterview)}
            writingText={writing?.field === 'mesExample' ? writing.text : ''}
            writing={writing?.field === 'mesExample'}
            locked={busy}
            error={errors.mesExample}
            onEdit={editDialogue}
            onRewrite={(direction) => void start('mesExample', direction)}
            onStop={() => void stop()}
          />
          <ReviewTextCard
            title="System Prompt"
            value={detail.systemPrompt}
            rows={4}
            onChange={(v) => editText('systemPrompt', v)}
          />
          <ReviewLorebookCard
            entries={detail.lorebook}
            handEdited={handEdited}
            kept={kept}
            open={loreOpen}
            onOpenChange={setLoreOpen}
            onToggle={toggleKeep}
            onEdit={setEditingLore}
            writing={writing?.field === 'lorebook'}
            locked={busy}
            error={errors.lorebook}
            onRewrite={(direction) => void start('lorebook', direction)}
            onStop={() => void stop()}
          />
        </div>
      </div>

      {loreEditing !== null && (
        <ReviewLoreEntryModal
          entry={detail.lorebook[loreEditing]}
          onSave={(entry) => saveLore(loreEditing, entry)}
          onClose={() => setEditingLore(null)}
        />
      )}
    </div>
  );
});
