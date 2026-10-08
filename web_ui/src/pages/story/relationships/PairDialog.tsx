// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Add a pair or edit one (sketch S). Adding picks who feels it and about whom
// from two chip rows; either way the feeling, a note, what goes unspoken and
// trust 0-10 are set here. Web twin of RelationshipsSection._edit.

import { useState } from 'react';
import type { StoryRelationship } from '../../../storyTypes';
import { Dialog, KeyLabel, PickChip } from '../setup/primitives';
import type { Shift } from './relationshipEdits';

export function PairDialog({ names, rel, onSave, onCancel }: {
  names: string[];
  /** The pair being edited; null adds a new one. */
  rel: StoryRelationship | null;
  onSave: (shift: Shift) => void;
  onCancel: () => void;
}) {
  const [from, setFrom] = useState(rel?.from ?? names[0]);
  const [to, setTo] = useState(rel?.to ?? names.find((n) => n !== names[0]) ?? names[0]);
  const [feeling, setFeeling] = useState(rel?.feeling ?? '');
  const [note, setNote] = useState(rel?.note ?? '');
  const [subtext, setSubtext] = useState(rel?.subtext ?? '');
  const [trust, setTrust] = useState(rel?.trust ?? 5);
  const ready = feeling.trim() !== '' && from !== to;
  const submit = () => { if (ready) onSave({ from, to, feeling, note, subtext, trust, reason: 'Edited by hand.' }); };
  const pickFrom = (name: string) => {
    setFrom(name);
    // Nobody feels something about themselves: move "Sees" along if it was that person.
    if (name === to) setTo(names.find((n) => n !== name) ?? name);
  };
  return (
    <Dialog title={rel ? `${rel.from} → ${rel.to}` : 'Add pair'} wide testid="rel-dialog" onClose={onCancel} actions={(
      <>
        <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
        <button type="button" className="s-btn-primary" data-testid="story-dialog-confirm" disabled={!ready} onClick={submit}>
          {rel ? 'Save' : 'Add'}
        </button>
      </>
    )}>
      {!rel && (
        <>
          <KeyLabel>Who</KeyLabel>
          <div className="s-chips">
            {names.map((n) => <PickChip key={n} on={n === from} onClick={() => pickFrom(n)}>{n}</PickChip>)}
          </div>
          <KeyLabel>Sees</KeyLabel>
          <div className="s-chips">
            {names.filter((n) => n !== from).map((n) => <PickChip key={n} on={n === to} onClick={() => setTo(n)}>{n}</PickChip>)}
          </div>
        </>
      )}
      <input type="text" className="s-field" placeholder="Feeling (one or two words)" aria-label="Feeling" data-testid="rel-feeling"
        autoFocus value={feeling} onChange={(e) => setFeeling(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') submit(); }} />
      <input type="text" className="s-field" placeholder="Note (two or three words)" aria-label="Note" data-testid="rel-note"
        value={note} onChange={(e) => setNote(e.target.value)} />
      <input type="text" className="s-field" placeholder="Unspoken" aria-label="Unspoken" data-testid="rel-subtext"
        value={subtext} onChange={(e) => setSubtext(e.target.value)} />
      <label className="s-row nowrap s-small">
        <span>Trust {trust}/10</span>
        <input type="range" className="s-range" min={0} max={10} step={1} value={trust} data-testid="rel-trust"
          onChange={(e) => setTrust(Number(e.target.value))} />
      </label>
    </Dialog>
  );
}
