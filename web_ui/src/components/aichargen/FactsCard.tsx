// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Profile step's "Also written from the interview" card: every Front
// Porch field the identity pass filled, editable, and "Re-read from the
// profile". The opening stance is shown read only (bond and trust are set on
// the desktop's Realism step). While the profile is rewritten the card dims
// and says it will be read again; while it is re-read it dims too.

import { useState } from 'react';
import { useLayout } from '../../hooks/useBreakpoint';
import { birthdayLabel, stanceOf, workDaysText, type Facts } from './profileApi';
import { CloseIcon, RewriteIcon } from './creatorIcons';

type ListKey = 'ambitions' | 'likes' | 'dislikes' | 'intimateInto' | 'intimateNotInto';

export function FactsCard({
  facts,
  onChange,
  nsfw,
  age,
  rewriting,
  rereading,
  onReread,
}: {
  facts: Facts;
  onChange: (f: Facts) => void;
  nsfw: boolean;
  age: string;
  /** The profile is being rewritten; the facts are read after it. */
  rewriting: boolean;
  /** The facts are being read again. */
  rereading: boolean;
  onReread: () => void;
}) {
  const { isPhone } = useLayout();
  const dim = rewriting || rereading;
  const set = (p: Partial<Facts>) => onChange({ ...facts, ...p });
  const text = (key: 'birthday' | 'occupation' | 'currentTask', label: string) => (
    <label className="cg-field cg-p-fact">
      <span className="cg-field-label">{label}</span>
      <input value={facts[key]} disabled={dim} onChange={(e) => set({ [key]: e.target.value })} />
    </label>
  );
  const chips = (key: ListKey, label: string) => (
    <div className="cg-field cg-p-fact">
      <span className="cg-field-label">{label}</span>
      <Chips values={facts[key]} disabled={dim} label={label} onChange={(v) => set({ [key]: v })} />
    </div>
  );
  return (
    <section
      className={`cg-g-card cg-p-facts${dim ? ' dim' : ''}`}
      aria-label="Also written from the interview"
      aria-busy={dim}
      data-testid="facts-card"
    >
      <div className="cg-p-facts-head">
        <div className="cg-p-facts-title">
          <h3>Also written from the interview</h3>
          <span className={rewriting ? 'cg-p-reread-note' : 'cg-p-caption'}>
            {rewriting
              ? 'Re-read after the rewrite'
              : isPhone
                ? 'Every Front Porch field is filled whether or not you use it. Mood, time of day and outfit follow the greeting.'
                : 'Every Front Porch field is filled whether or not you use it. Mood, time of day and outfit follow once the greeting exists.'}
          </span>
        </div>
        <button type="button" className="cg-p-small-btn" disabled={dim} onClick={onReread}>
          <RewriteIcon size={16} />
          Re-read from the profile
        </button>
      </div>
      <div className="cg-p-grid3">
        {text('birthday', birthdayLabel(age, isPhone))}
        {text('occupation', 'OCCUPATION')}
        <label className="cg-field cg-p-fact">
          <span className="cg-field-label">HOURS · WORK DAYS</span>
          {/* The days are set on the desktop's Realism step: a muted note
              beside the field, under it when there is no room. */}
          <span className="cg-p-hours">
            <input
              value={facts.hours}
              placeholder="No set hours"
              disabled={dim}
              onChange={(e) => set({ hours: e.target.value })}
            />
            {facts.hours.trim() && <span className="cg-p-days">· {workDaysText(facts.workDays)}</span>}
          </span>
        </label>
      </div>
      <div className="cg-p-grid2">
        {text('currentTask', 'OPENING TASK')}
        <label className="cg-field cg-p-fact">
          <span className="cg-field-label">
            OPENING STANCE TOWARD <span className="cg-p-macro">{'{{user}}'}</span>
          </span>
          <input value={stanceOf(facts)} readOnly aria-readonly="true" className="cg-p-readonly" />
        </label>
        {chips('ambitions', 'AMBITIONS')}
        {chips('likes', 'WARMS TO')}
        {chips('dislikes', 'PUT OFF BY')}
        {nsfw && (
          <div className="cg-field cg-p-fact">
            <span className="cg-field-label">INTIMATE PREFERENCES · 18+ IS ON</span>
            <div className="cg-p-intimate">
              <span className="cg-p-sub-label">into</span>
              <Chips
                values={facts.intimateInto}
                disabled={dim}
                label="Into"
                onChange={(v) => set({ intimateInto: v })}
              />
              <span className="cg-p-sub-label">not into</span>
              <Chips
                values={facts.intimateNotInto}
                disabled={dim}
                label="Not into"
                onChange={(v) => set({ intimateNotInto: v })}
              />
            </div>
          </div>
        )}
      </div>
      <label className="cg-field cg-p-fact">
        <span className="cg-field-label">CREATOR NOTES · THE PITCH</span>
        <textarea
          rows={2}
          value={facts.creatorNotes}
          disabled={dim}
          onChange={(e) => set({ creatorNotes: e.target.value })}
        />
      </label>
    </section>
  );
}

/** A chip list: each chip removable, then "+ add" (a small field while
 *  adding). */
function Chips({
  values,
  onChange,
  disabled,
  label,
}: {
  values: string[];
  onChange: (v: string[]) => void;
  disabled: boolean;
  label: string;
}) {
  const [adding, setAdding] = useState(false);
  const [draft, setDraft] = useState('');
  const commit = () => {
    if (disabled) {
      setDraft('');
      setAdding(false);
      return;
    }
    const v = draft.trim();
    if (v && !values.includes(v)) onChange([...values, v]);
    setDraft('');
    setAdding(false);
  };
  return (
    <div className="cg-p-chips">
      {values.map((v, i) => (
        <span className="cg-p-chip" key={`${i}-${v}`}>
          {v}
          <button
            type="button"
            className="cg-p-chip-x"
            aria-label={`Remove ${v}`}
            disabled={disabled}
            onClick={() => onChange(values.filter((_, j) => j !== i))}
          >
            <CloseIcon />
          </button>
        </span>
      ))}
      {adding ? (
        <input
          className="cg-p-chip-input"
          aria-label={`Add to ${label.toLowerCase()}`}
          autoFocus
          disabled={disabled}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              commit();
            } else if (e.key === 'Escape') {
              setDraft('');
              setAdding(false);
            }
          }}
        />
      ) : (
        <button
          type="button"
          className="cg-p-chip-add"
          aria-label={`Add to ${label.toLowerCase()}`}
          disabled={disabled}
          onClick={() => setAdding(true)}
        >
          + add
        </button>
      )}
    </div>
  );
}
