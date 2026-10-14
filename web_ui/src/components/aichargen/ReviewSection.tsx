// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The two review rewrites at the foot of the phone's Greetings step (the
// desktop's Review step): the example dialogue (edit it, or steer and
// Regenerate) and the lorebook (its first entries, hand-edited ones marked,
// steer and Rewrite the lorebook, which keeps those). Each runs on the relay
// (chargen_rewrite_*) and is saved only when done; Stop leaves it as it was.

import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from 'react';
import { ApiError } from '../../api/client';
import type { WsEvent } from '../../api/ws';
import { MacroField } from '../MacroField';
import { ReviewRewriteCard } from './ReviewRewriteCard';
import {
  dialogueSubtitle,
  loadReview,
  loreRowsOf,
  saveExampleDialogue,
  startReviewRewrite,
  stopReviewRewrite,
  type Review,
} from './profileApi';

type Field = 'mesExample' | 'lorebook';

const SAVE_PAUSE_MS = 700;

const messageOf = (err: unknown, fallback: string) =>
  err instanceof ApiError && err.message ? err.message : fallback;

/** The Greetings step's socket hands this section its events (one socket
 *  per step): `chargen_rewrite_*`, and `connected` to ask again. */
export type ReviewSectionHandle = { onEvent: (e: WsEvent) => void };

type Props = {
  characterId: string;
  /** Opens the character editor (its lorebook), after saving what was typed. */
  onOpenEditor?: () => void;
  /** Something else (a greeting) is being written. */
  locked: boolean;
  onWritingChange?: (writing: boolean) => void;
};

export const ReviewSection = forwardRef<ReviewSectionHandle, Props>(function ReviewSection(
  { characterId: id, locked, onWritingChange, onOpenEditor },
  ref,
) {
  const [review, setReview] = useState<Review | null>(null);
  const [writing, setWriting] = useState<{ field: Field; text: string } | null>(null);
  const [errors, setErrors] = useState<Partial<Record<Field, string>>>({});
  const writingRef = useRef(writing);
  writingRef.current = writing;
  const timer = useRef<number | undefined>(undefined);

  const refresh = useCallback(async () => {
    try {
      const r = await loadReview(id);
      setReview(r);
      const w = r.writing;
      setWriting((cur) => (w === 'mesExample' || w === 'lorebook' ? (cur?.field === w ? cur : { field: w, text: '' }) : null));
    } catch {
      // The next reconnect asks again.
    }
  }, [id]);

  useEffect(() => {
    void refresh();
  }, [refresh]);
  useEffect(() => {
    onWritingChange?.(writing !== null);
  }, [writing, onWritingChange]);
  useEffect(() => () => window.clearTimeout(timer.current), []);

  useImperativeHandle(
    ref,
    () => ({
      onEvent: (e: WsEvent) => {
        if (e.event === 'connected') {
          if (writingRef.current) void refresh();
          return;
        }
        if (!e.event.startsWith('chargen_rewrite_') || String(e.characterId ?? '') !== id) return;
        const field = e.field === 'lorebook' ? 'lorebook' : 'mesExample';
        if (e.event === 'chargen_rewrite_progress') {
          setWriting((w) => (w && w.field === field ? { field, text: e.text ?? '' } : w));
          return;
        }
        setWriting(null);
        if (e.event === 'chargen_rewrite_done') {
          setReview((r) =>
            r && (field === 'lorebook' ? { ...r, lorebook: loreRowsOf(e.lorebook) } : { ...r, mesExample: e.text ?? '' }),
          );
        } else if (e.event === 'chargen_rewrite_error') {
          setErrors((x) => ({ ...x, [field]: e.error || 'The rewrite failed.' }));
        }
      },
    }),
    [id, refresh],
  );

  const start = async (field: Field, direction: string) => {
    if (writingRef.current) return;
    window.clearTimeout(timer.current);
    if (field === 'mesExample' && review) await saveExampleDialogue(id, review.mesExample).catch(() => undefined);
    setErrors((x) => ({ ...x, [field]: undefined }));
    const w = { field, text: '' };
    writingRef.current = w;
    setWriting(w);
    try {
      await startReviewRewrite(id, field, direction);
    } catch (err) {
      if (writingRef.current === w) setWriting(null);
      setErrors((x) => ({ ...x, [field]: messageOf(err, 'The rewrite could not be started. Try again.') }));
    }
  };

  const stop = async () => {
    try {
      if ((await stopReviewRewrite(id)).stopped) setWriting(null);
    } catch (err) {
      const f = writingRef.current?.field ?? 'mesExample';
      setErrors((x) => ({ ...x, [f]: messageOf(err, 'Stop did not reach the app. Try again.') }));
    }
  };

  const editDialogue = (text: string) => {
    setReview((r) => r && { ...r, mesExample: text });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      saveExampleDialogue(id, text).catch((err) =>
        setErrors((x) => ({ ...x, mesExample: messageOf(err, 'Your edit could not be saved.') })),
      );
    }, SAVE_PAUSE_MS);
  };

  if (!review) return null;
  const busy = locked || writing !== null;
  const rows = review.lorebook;
  return (
    <div className="cg-review-cards" data-testid="review-cards">
      <ReviewRewriteCard
        title="Example dialogue"
        subtitle={dialogueSubtitle(review.sex)}
        placeholder="Steer it (optional), e.g. shorter lines, more bite"
        button="Regenerate"
        writing={writing?.field === 'mesExample'}
        locked={busy}
        error={errors.mesExample}
        onRewrite={(d) => void start('mesExample', d)}
        onStop={() => void stop()}
      >
        {writing?.field === 'mesExample' ? (
          <div className="cg-g-stream" aria-live="polite">
            {writing.text}
            <span className="cg-g-caret" />
          </div>
        ) : (
          <MacroField
            label="Example dialogue"
            value={review.mesExample}
            onChange={editDialogue}
            rows={5}
            ariaLabel="Example dialogue text"
            showHead={false}
          />
        )}
      </ReviewRewriteCard>
      <ReviewRewriteCard
        title="Lorebook"
        subtitle={`${rows.length} ${rows.length === 1 ? 'entry' : 'entries'}`}
        headAction={
          onOpenEditor && (
            <button type="button" className="cg-p-text-btn" disabled={busy} onClick={onOpenEditor}>
              Open the lorebook editor
            </button>
          )
        }
        placeholder="Steer it (optional), e.g. more about the town, less about the sea"
        button="Rewrite the lorebook"
        caption="Rewrites the entries from the profile and your direction. An entry you edited by hand is kept."
        writing={writing?.field === 'lorebook'}
        locked={busy}
        error={errors.lorebook}
        onRewrite={(d) => void start('lorebook', d)}
        onStop={() => void stop()}
      >
        <div className="cg-lore-rows">
          {rows.slice(0, 3).map((r, i) => (
            <div className="cg-lore-row" key={`${r.name}-${i}`}>
              <span className="cg-lore-name">{r.name || 'Untitled'}</span>
              <span className="cg-lore-preview">{r.content}</span>
              {r.handEdited && <span className="cg-lore-pill">Edited by hand</span>}
            </div>
          ))}
          {rows.length > 3 && <span className="cg-lore-more">and {rows.length - 3} more</span>}
        </div>
      </ReviewRewriteCard>
    </div>
  );
});
