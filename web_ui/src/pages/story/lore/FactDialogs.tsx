// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The continuity ledger's two dialogs (sketch T): Add / Edit a fact (a category
// chip row and three fields) and "Retire from which scene?". Same titles and
// hints as the desktop's lore_section.facts.dart.

import { useState, type KeyboardEvent } from 'react';
import type { ContinuityFact, StoryProject } from '../../../storyTypes';
import { Dialog, PickChip } from '../setup/primitives';
import { orderedScenes, sceneLabel } from '../storyShape';
import { FACT_CATEGORIES, type FactFields } from './continuity';

export function FactDialog({ fact, onSave, onCancel }: {
  /** The fact being edited; null adds a new one. */
  fact: ContinuityFact | null;
  onSave: (fields: FactFields) => void;
  onCancel: () => void;
}) {
  const [category, setCategory] = useState(fact?.category ?? 'Fact');
  const [key, setKey] = useState(fact?.key ?? '');
  const [value, setValue] = useState(fact?.value ?? '');
  const [entity, setEntity] = useState(fact?.entity ?? '');
  // A fact needs its subject; a new one needs what is true of it, or the ledger would drop it.
  const ready = key.trim() !== '' && (fact !== null || value.trim() !== '');
  const submit = () => { if (ready) onSave({ category, key, value, entity }); };
  const enter = (e: KeyboardEvent) => { if (e.key === 'Enter') submit(); };
  return (
    <Dialog title={fact ? 'Edit fact' : 'Add fact'} wide testid="fact-dialog" onClose={onCancel} actions={(
      <>
        <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
        <button type="button" className="s-btn-primary" data-testid="story-dialog-confirm" disabled={!ready} onClick={submit}>
          {fact ? 'Save' : 'Add'}
        </button>
      </>
    )}>
      <div className="s-chips">
        {FACT_CATEGORIES.map((c) => <PickChip key={c} on={c === category} onClick={() => setCategory(c)}>{c}</PickChip>)}
      </div>
      <input type="text" className="s-field" placeholder="What (e.g. Teodor's left hand)" aria-label="What" data-testid="fact-key"
        autoFocus value={key} onChange={(e) => setKey(e.target.value)} onKeyDown={enter} />
      <input type="text" className="s-field" placeholder="Is (e.g. burned, bandaged)" aria-label="Is" data-testid="fact-value"
        value={value} onChange={(e) => setValue(e.target.value)} onKeyDown={enter} />
      <input type="text" className="s-field" placeholder="Who or where it belongs to" aria-label="Who or where it belongs to" data-testid="fact-entity"
        value={entity} onChange={(e) => setEntity(e.target.value)} onKeyDown={enter} />
    </Dialog>
  );
}

/** Every scene in story order; a tap names the one the fact stops being true at. */
export function RetireDialog({ p, fact, onPick, onCancel }: {
  p: StoryProject;
  fact: ContinuityFact;
  onPick: (sceneId: string) => void;
  onCancel: () => void;
}) {
  const refs = orderedScenes(p).filter((r) => !!r.scene.id);
  return (
    <Dialog title={`Retire “${fact.key}” from which scene?`} wide testid="fact-retire-dialog" onClose={onCancel} actions={(
      <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
    )}>
      {refs.length === 0 && <div className="body">There are no scenes yet.</div>}
      <div className="s-col" style={{ gap: 0 }}>
        {refs.map((r) => (
          <button key={r.scene.id} type="button" className="s-listrow" onClick={() => onPick(r.scene.id ?? '')}>
            <span className="s-mono" style={{ width: 44, flex: 'none' }}>{sceneLabel(p, r.act, r.index)}</span>
            <span className="s-grow s-ell">{r.scene.title}</span>
          </button>
        ))}
      </div>
    </Dialog>
  );
}
