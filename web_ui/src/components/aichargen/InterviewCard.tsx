// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Interview card at the end of the Output step
// (docs/design/creator-ui-spec.md, Interview card): the questions the
// character is asked before the profile is written, each editable,
// reorderable by its handle (pointer drag, mouse or touch, or the arrow
// keys), removable unless it is conditional, up to twelve, and a reset to
// the standard set. An "Interview this character" switch skips the whole
// interview — the create then sends `interviewQuestions: []`, which asks
// nothing — while every row stays exactly as it is; editing a row or
// adding one turns the interview back on. The wording follows the
// Perspective, Tense and Sex fields above: the relay renders it, and a
// re-fetch rewords every row not edited. Editing waits until the first
// wording arrives.

import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent } from 'react';
import { useLayout } from '../../hooks/useBreakpoint';
import type { ChargenForm } from './chargenForm';
import { CloseIcon, DotsIcon, PlusIcon } from './creatorIcons';
import {
  INTERVIEW_CAP,
  addRow,
  asksNothing,
  countCaption,
  editRow,
  followsCaption,
  isEdited,
  isStandardList,
  loadStandard,
  moveRow,
  removeRow,
  rowText,
  rowsFrom,
  voicePill,
  type InterviewRow,
  type StandardSet,
} from './interviewRows';

const INTRO_DESKTOP =
  'The character is interviewed before the profile is written. Every answer reaches every later step. Edit any question, drag to reorder, or add your own. Each one is a model call, so fewer is faster on a local model. Voice first and appearance last works best.';
const INTRO_PHONE =
  'Asked before the profile is written. Each question is a model call. Voice first, appearance last works best.';
const CONDITION_PILL = {
  relationship: 'Asked only when a relationship is set',
  nsfw: 'Asked only when 18+ is on',
} as const;
const SEX_SETTLE_MS = 250;
/** How near the edge of the scrolling area a held row scrolls it, and by
 *  how much each frame. */
const SCROLL_EDGE = 48;
const SCROLL_STEP = 12;

/** The nearest ancestor that scrolls (the creator's content column), else
 *  the page. */
function scrollingBox(el: Element | null): Element | null {
  for (let p = el?.parentElement; p; p = p.parentElement) {
    const y = getComputedStyle(p).overflowY;
    if ((y === 'auto' || y === 'scroll') && p.scrollHeight > p.clientHeight) return p;
  }
  return document.scrollingElement;
}

export function InterviewCard({ form, set }: { form: ChargenForm; set: (p: Partial<ChargenForm>) => void }) {
  const { isPhone } = useLayout();
  const [standard, setStandard] = useState<StandardSet | null>(null);
  const [loadFailed, setLoadFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);
  // Sex is typed: the wording follows it once the typing pauses.
  const [sex, setSex] = useState(form.sex);
  useEffect(() => {
    if (form.sex === sex) return;
    const t = setTimeout(() => setSex(form.sex), SEX_SETTLE_MS);
    return () => clearTimeout(t);
  }, [form.sex, sex]);

  const { narrativePerspective: perspective, narrativeTense: tense } = form;
  // The voice the loaded set was rendered for: until it matches, the rows
  // still show the previous wording and stay locked.
  const [loadedFor, setLoadedFor] = useState('');
  const wantFor = `${perspective}|${tense}|${sex}`;
  useEffect(() => {
    let alive = true;
    loadStandard(perspective, tense, sex)
      .then((s) => {
        if (!alive) return;
        setStandard(s);
        setLoadedFor(`${perspective}|${tense}|${sex}`);
        setLoadFailed(false);
      })
      .catch((err) => {
        console.warn('[creator] the interview questions could not be loaded', err);
        if (alive) setLoadFailed(true);
      });
    return () => {
      alive = false;
    };
  }, [perspective, tense, sex, attempt]);

  const rows = form.interviewQuestions ?? (standard ? rowsFrom(standard.rows) : []);
  const rowsRef = useRef(rows);
  rowsRef.current = rows;
  const textByKey = useMemo(
    () => Object.fromEntries((standard?.rows ?? []).map((q) => [q.key, q.text])),
    [standard],
  );
  const locked = standard === null || loadedFor !== wantFor;

  const commit = (next: InterviewRow[], wake = false) => {
    if (next === rowsRef.current) return;
    rowsRef.current = next;
    // Editing or adding a question means the user wants the answer: a
    // skipped interview turns itself back on. Moves and removes do not.
    set({
      interviewQuestions: standard && isStandardList(next, standard.rows) ? null : next,
      ...(wake ? { interviewSkipped: false } : {}),
    });
  };

  // After Add or a keyboard move, the row's box or handle keeps the focus.
  const focusNext = useRef<{ id: string; part: 'text' | 'handle' } | null>(null);
  const rowEls = useRef(new Map<string, HTMLDivElement>());
  useEffect(() => {
    const f = focusNext.current;
    if (!f) return;
    focusNext.current = null;
    rowEls.current.get(f.id)?.querySelector<HTMLElement>(f.part === 'text' ? 'textarea' : '.cg-iv-handle')?.focus();
  });

  // Drag: the list holds the pointer (a row moves in the page as it is
  // dragged, and a moved element can lose its capture); a row trades places
  // as the pointer crosses a neighbour's middle. Held near the top or
  // bottom of the scrolling area, the page scrolls on, so a row can travel
  // the whole list on a phone.
  const listEl = useRef<HTMLDivElement>(null);
  const [dragId, setDragId] = useState<string | null>(null);
  const drag = useRef<{ id: string | null; y: number; frame: number; box: Element | null }>({
    id: null,
    y: 0,
    frame: 0,
    box: null,
  });
  const commitRef = useRef(commit);
  commitRef.current = commit;
  const middle = (id: string) => {
    const r = rowEls.current.get(id)?.getBoundingClientRect();
    return r ? r.top + r.height / 2 : 0;
  };
  const reorderAt = (y: number) => {
    const list = rowsRef.current;
    const from = list.findIndex((r) => r.id === drag.current.id);
    if (from < 0) return;
    let to = from;
    while (to > 0 && y < middle(list[to - 1].id)) to -= 1;
    if (to === from) while (to < list.length - 1 && y > middle(list[to + 1].id)) to += 1;
    commitRef.current(moveRow(list, from, to));
  };
  const autoScroll = () => {
    const d = drag.current;
    d.frame = 0;
    const box = d.box;
    if (!d.id || !box) return;
    const edge = box === document.scrollingElement ? { top: 0, bottom: window.innerHeight } : box.getBoundingClientRect();
    const dy = d.y < edge.top + SCROLL_EDGE ? -SCROLL_STEP : d.y > edge.bottom - SCROLL_EDGE ? SCROLL_STEP : 0;
    const before = box.scrollTop;
    if (dy) box.scrollTop += dy;
    if (box.scrollTop === before) return;
    reorderAt(d.y);
    d.frame = requestAnimationFrame(autoScroll);
  };
  const startDrag = (e: PointerEvent<HTMLButtonElement>, id: string) => {
    if (locked || e.button !== 0) return;
    e.preventDefault();
    listEl.current?.setPointerCapture?.(e.pointerId);
    drag.current = { id, y: e.clientY, frame: 0, box: scrollingBox(listEl.current) };
    setDragId(id);
  };
  const dragMove = (e: PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d.id) return;
    d.y = e.clientY;
    reorderAt(e.clientY);
    if (!d.frame && typeof requestAnimationFrame === 'function') d.frame = requestAnimationFrame(autoScroll);
  };
  const endDrag = () => {
    const d = drag.current;
    if (d.frame) cancelAnimationFrame(d.frame);
    drag.current = { id: null, y: 0, frame: 0, box: null };
    setDragId(null);
  };
  useEffect(() => {
    const d = drag;
    return () => {
      if (d.current.frame) cancelAnimationFrame(d.current.frame);
    };
  }, []);
  const keyMove = (e: KeyboardEvent<HTMLButtonElement>, index: number, id: string) => {
    const to = e.key === 'ArrowUp' ? index - 1 : e.key === 'ArrowDown' ? index + 1 : index;
    if (to === index || to < 0 || to >= rows.length) return;
    e.preventDefault();
    focusNext.current = { id, part: 'handle' };
    commit(moveRow(rows, index, to));
  };

  const add = () => {
    const next = addRow(rows);
    if (next === rows) return;
    focusNext.current = { id: next[next.length - 1].id, part: 'text' };
    commit(next, true);
  };

  const skipped = form.interviewSkipped;
  const skipSwitch = (
    <label className="cg-iv-skip">
      <input
        type="checkbox"
        role="switch"
        aria-label="Interview this character"
        data-testid="interview-skip"
        checked={!skipped}
        onChange={(e) => set({ interviewSkipped: !e.target.checked })}
      />
      <span>Interview this character</span>
    </label>
  );

  const pill = voicePill(perspective, tense);
  const reset = (
    <button
      type="button"
      className="cg-iv-reset"
      aria-label="Reset to the standard questions"
      onClick={() => set({ interviewQuestions: null, interviewSkipped: false })}
    >
      {isPhone ? 'Reset' : 'Reset to the standard questions'}
    </button>
  );

  return (
    <section className="cg-iv" aria-label="Interview" data-testid="interview-card">
      {isPhone ? (
        <div className="cg-iv-head">
          <div className="cg-iv-title-row">
            <h3 className="cg-iv-title">Interview</h3>
            {skipSwitch}
            {reset}
          </div>
          <p className="cg-iv-intro">{INTRO_PHONE}</p>
          <div className="cg-iv-voice">
            <span className="cg-iv-pill">{pill}</span>
          </div>
        </div>
      ) : (
        <div className="cg-iv-head">
          <div className="cg-iv-head-text">
            <div className="cg-iv-title-row">
              <h3 className="cg-iv-title">Interview</h3>
              {skipSwitch}
            </div>
            <p className="cg-iv-intro">{INTRO_DESKTOP}</p>
            <div className="cg-iv-voice">
              <span className="cg-iv-pill">{pill}</span>
              <span className="cg-iv-follows">
                {followsCaption(perspective, standard?.pronouns ?? { subject: 'they', possessive: 'their' })}
              </span>
            </div>
          </div>
          {reset}
        </div>
      )}

      {loadFailed && (
        <p className="cg-iv-error" role="alert">
          The questions could not be loaded. Check the connection, then try again.{' '}
          <button type="button" className="cg-iv-retry" onClick={() => setAttempt((a) => a + 1)}>
            Try again
          </button>
        </p>
      )}
      {locked && rows.length === 0 && !loadFailed && <p className="cg-iv-loading">Loading the questions…</p>}

      <div
        ref={listEl}
        className={skipped ? 'cg-iv-rows dimmed' : 'cg-iv-rows'}
        data-testid="interview-rows"
        onPointerMove={dragMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onLostPointerCapture={endDrag}
      >
        {rows.map((row, i) => (
          <QuestionRow
            key={row.id}
            row={row}
            n={i + 1}
            text={rowText(row, textByKey)}
            locked={locked}
            dragging={dragId === row.id}
            rowRef={(el) => {
              if (el) rowEls.current.set(row.id, el);
              else rowEls.current.delete(row.id);
            }}
            onText={(t) => commit(editRow(rows, row.id, t), true)}
            onRemove={() => commit(removeRow(rows, row.id))}
            onHandleDown={(e) => startDrag(e, row.id)}
            onHandleKey={(e) => keyMove(e, i, row.id)}
          />
        ))}
      </div>

      <div className="cg-iv-foot">
        <button type="button" className="cg-iv-add" disabled={locked || rows.length >= INTERVIEW_CAP} onClick={add}>
          <PlusIcon />
          Add a question
        </button>
        <span className="cg-iv-count" data-testid="interview-count">
          {countCaption(rows.length, isPhone, skipped || asksNothing(rows, textByKey))}
        </span>
      </div>
    </section>
  );
}

function QuestionRow({
  row,
  n,
  text,
  locked,
  dragging,
  rowRef,
  onText,
  onRemove,
  onHandleDown,
  onHandleKey,
}: {
  row: InterviewRow;
  n: number;
  text: string;
  locked: boolean;
  dragging: boolean;
  rowRef: (el: HTMLDivElement | null) => void;
  onText: (text: string) => void;
  onRemove: () => void;
  onHandleDown: (e: PointerEvent<HTMLButtonElement>) => void;
  onHandleKey: (e: KeyboardEvent<HTMLButtonElement>) => void;
}) {
  const edited = isEdited(row);
  const label =
    row.condition === 'relationship' ? 'Relationship question' : row.condition === 'nsfw' ? '18+ question' : `Question ${n}`;
  const cls = ['cg-iv-row', row.condition && 'conditional', edited && 'edited', dragging && 'dragging']
    .filter(Boolean)
    .join(' ');
  return (
    <div ref={rowRef} className={cls} data-testid="interview-row">
      <button
        type="button"
        className="cg-iv-handle"
        aria-label={`Move question ${n}`}
        title="Drag to reorder"
        disabled={locked}
        onPointerDown={onHandleDown}
        onKeyDown={onHandleKey}
      >
        <DotsIcon />
      </button>
      <span className="cg-iv-num">{n}</span>
      <div className="cg-iv-body">
        <GrowingText value={text} label={label} disabled={locked} onChange={onText} />
        {(row.condition || edited) && (
          <div className="cg-iv-pills">
            {row.condition && <span className="cg-iv-cond">{CONDITION_PILL[row.condition]}</span>}
            {edited && <span className="cg-iv-edited">Edited · kept as written</span>}
          </div>
        )}
      </div>
      {row.condition ? (
        <span className="cg-iv-spacer" />
      ) : (
        <button
          type="button"
          className="cg-iv-remove"
          aria-label={`Remove question ${n}`}
          disabled={locked}
          onClick={onRemove}
        >
          <CloseIcon size={18} />
        </button>
      )}
    </div>
  );
}

/** A text area as tall as its text (no resize handle), re-measured when its
 *  width changes. */
function GrowingText({
  value,
  label,
  disabled,
  onChange,
}: {
  value: string;
  label: string;
  disabled: boolean;
  onChange: (v: string) => void;
}) {
  const ref = useRef<HTMLTextAreaElement>(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const fit = () => {
      el.style.height = 'auto';
      const border = el.offsetHeight - el.clientHeight;
      el.style.height = `${el.scrollHeight + border}px`;
    };
    fit();
    if (typeof ResizeObserver === 'undefined') return;
    let width = el.clientWidth;
    const watch = new ResizeObserver(() => {
      if (el.clientWidth === width) return;
      width = el.clientWidth;
      fit();
    });
    watch.observe(el);
    return () => watch.disconnect();
  }, [value]);
  return (
    <textarea
      ref={ref}
      className="cg-iv-text"
      rows={1}
      aria-label={label}
      value={value}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}
