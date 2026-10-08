// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Relationships (sketch S): the grid stays the size of its cells; read a row as
// "how this person sees that one"; the selected pair shows its history beside
// it. Phones get a list of pairs instead of the grid. Web twin of the desktop
// RelationshipsSection.

import { useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import { useStory } from '../hooks/useStory';
import { removePairCopy } from './story/confirmCopy';
import { Matrix } from './story/relationships/Matrix';
import { PairDetail } from './story/relationships/PairDetail';
import { PairDialog } from './story/relationships/PairDialog';
import {
  feelingTone, findPair, recordedAfter, relationshipNames, removePair, shiftRelationship, type Pair, type Shift,
} from './story/relationships/relationshipEdits';
import { Chip, StudioLoading, StudioShell } from './story/StudioShell';
import { useNarrow } from './story/setup/primitives';
import { useConfirm } from './story/useConfirm';
import { EmptyState } from './story/world/EmptyState';

export function StoryRelationshipsPage() {
  const { id = '' } = useParams();
  const { project: p, status, error, stop, save } = useStory(id);
  const narrow = useNarrow();
  const [picked, setPicked] = useState<Pair | null>(null);
  // null closes the dialog; { rel: null } is Add pair.
  const [dialogFor, setDialogFor] = useState<{ rel: Pair | null } | null>(null);
  const detail = useRef<HTMLDivElement | null>(null);
  const { ask, dialog } = useConfirm();

  if (!p) return <StudioLoading error={error} />;

  const rels = p.relationships ?? [];
  const names = relationshipNames(p);
  const first = rels[0] ? { from: rels[0].from, to: rels[0].to } : null;
  const selected = picked ?? first;
  const rel = selected ? findPair(rels, selected.from, selected.to) : undefined;
  const editing = dialogFor?.rel ? findPair(rels, dialogFor.rel.from, dialogFor.rel.to) ?? null : null;

  const choose = (pair: Pair) => {
    setPicked(pair);
    // On a phone the card is under the list; bring it into view.
    if (narrow) requestAnimationFrame(() => detail.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }));
  };
  const submit = (s: Shift) => {
    setDialogFor(null);
    void save({ relationships: shiftRelationship(rels, s) });
    setPicked({ from: s.from, to: s.to });
  };
  const remove = (r: Pair) => ask(removePairCopy(r.from, r.to), () => {
    setPicked(null);
    void save({ relationships: removePair(rels, r.from, r.to) });
  });
  const card = rel && (
    <PairDetail p={p} rel={rel} onEdit={() => setDialogFor({ rel })} onRemove={() => remove(rel)} />
  );

  return (
    <StudioShell id={id} project={p} section="relationships" status={status} error={error} onStop={stop}>
      <div className="s-row nowrap">
        <span className="s-grow s-muted s-body">{recordedAfter(p)}</span>
        <button type="button" className="s-btn-quiet" data-testid="rel-add" disabled={names.length < 2}
          onClick={() => setDialogFor({ rel: null })}>+ Add pair</button>
      </div>

      {names.length < 2 || rels.length === 0 ? (
        <EmptyState testid="rel-empty" title="No relationships yet" detail={p.engine_mode === 'studio'
          ? 'Studio records who feels what about whom after every scene. Write a scene, or add a pair yourself.'
          : 'The Quick engine does not track relationships. Switch the story to Studio under Setup, or add a pair yourself.'} />
      ) : narrow ? (
        <div className="s-col" style={{ gap: 6 }}>
          {rels.map((r) => (
            <button key={`${r.from}->${r.to}`} type="button" className="s-card tap s-pair" data-testid={`rel-pair-${r.from}-${r.to}`}
              onClick={() => choose({ from: r.from, to: r.to })}>
              <span className="s-grow s-bold">{r.from} → {r.to}</span>
              <Chip tone={feelingTone(r)}>{r.feeling || '—'}</Chip>
            </button>
          ))}
          <div ref={detail}>{card}</div>
        </div>
      ) : (
        <div className="s-rel-cols">
          <section className="s-card s-rel-matrix">
            <Matrix names={names} rels={rels} selected={selected} onSelect={choose} />
          </section>
          {card}
        </div>
      )}

      {dialogFor && names.length >= 2 && (
        <PairDialog names={names} rel={editing} onSave={submit} onCancel={() => setDialogFor(null)} />
      )}
      {dialog}
    </StudioShell>
  );
}
