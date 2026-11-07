// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The three tabs of Lore & continuity (sketch T): the continuity ledger (one
// row per fact with its ⋯ menu), the lore entries, and Story so far (a card per
// sequence). Web twins of lore_section.dart's _continuityTab / _loreTab /
// _soFarTab.

import type { StoryLoreEntry, StoryProject } from '../../../storyTypes';
import { MenuButton } from '../setup/primitives';
import { Chip } from '../StudioShell';
import { EmptyState } from '../world/EmptyState';
import { DocumentIcon } from '../world/WorldIcons';
import { isRetired } from './continuity';
import { factRows, factWhen, fileRefs, FILE_PREFIX, loreFrom, soFarBlocks } from './loreShape';
import { isWorldLore, placeRefs } from '../setup/worldPick';

export function FactsTab({ p, onEdit, onRetire, onForget }: {
  p: StoryProject;
  onEdit: (index: number) => void;
  onRetire: (index: number) => void;
  onForget: (index: number) => void;
}) {
  const facts = p.continuity ?? [];
  if (facts.length === 0) {
    return (
      <EmptyState testid="lore-empty-facts" title="No facts yet" detail={p.engine_mode === 'studio'
        ? 'Studio records hard facts after every scene: scars, objects, promises, places. Add one yourself with Add fact.'
        : 'The Quick engine does not keep a ledger. Switch the story to Studio under Setup, or add facts yourself.'} />
    );
  }
  return (
    <section className="s-card" data-testid="lore-facts">
      {factRows(facts).map(({ fact: f, index }) => {
        const retired = isRetired(f);
        return (
          <div key={index} className="s-fact">
            <Chip tone={retired ? '' : 'honey'}>{retired ? 'Retired' : f.category}</Chip>
            <span className={`s-fact-text${retired ? ' retired' : ''}`}>
              <b>{f.key}</b> · {f.value}{f.entity && <span className="s-muted"> ({f.entity})</span>}
            </span>
            <span className="s-fact-end">
              <span className="s-mono">{factWhen(p, f)}</span>
              <MenuButton label={`More for ${f.key}`} testid={`fact-menu-${f.key}`} entries={[
                { label: 'Edit…', onSelect: () => onEdit(index) },
                // Only a live fact can be retired.
                ...(retired ? [] : [{ label: 'Retire from scene…', onSelect: () => onRetire(index) }]),
                { label: 'Forget…', danger: true, divider: true, onSelect: () => onForget(index) },
              ]} />
            </span>
          </div>
        );
      })}
    </section>
  );
}

/** The chips that say where a lore entry came from: a file, the story's world, and the place inside it. Twin of loreSourceChips. */
export function LoreSourceChips({ p, entry, placeNames }: {
  p: StoryProject;
  entry: StoryLoreEntry;
  /** Place id → name, from the relay's world summary; a place not in it (the root) gets no chip. */
  placeNames: Record<string, string>;
}) {
  const worldName = p.world_name?.trim() || 'the world';
  return (
    <>
      {fileRefs(entry).map((r) => <Chip key={r}><DocumentIcon />{r.slice(FILE_PREFIX.length)}</Chip>)}
      {isWorldLore(entry) && <Chip tone="honey">from {worldName}</Chip>}
      {isWorldLore(entry) && placeRefs(entry).map((id) => placeNames[id] && <Chip key={id}>{placeNames[id]}</Chip>)}
    </>
  );
}

export function LoreTab({ p, onRemove, placeNames = {} }: {
  p: StoryProject;
  onRemove: (index: number) => void;
  placeNames?: Record<string, string>;
}) {
  if (p.lore.length === 0) {
    return <EmptyState testid="lore-empty-lore" title="No lore yet" detail="Add a file, or let the story bible create some." />;
  }
  return (
    <section className="s-card" data-testid="lore-entries">
      {p.lore.map((l, i) => {
        const from = loreFrom(l);
        return (
          <div key={i} className="s-fact top">
            <div className="s-grow s-col" style={{ gap: 2 }}>
              <div className="s-row" style={{ gap: '4px 8px' }}>
                <span className="s-bold s-body">{l.topic}</span>
                <LoreSourceChips p={p} entry={l} placeNames={placeNames} />
                {from && <span className="s-mono">{from}</span>}
              </div>
              <span className="s-muted s-body">{l.detail}</span>
            </div>
            <MenuButton label={`More for ${l.topic}`} testid={`lore-menu-${l.topic}`}
              entries={[{ label: 'Remove…', danger: true, onSelect: () => onRemove(i) }]} />
          </div>
        );
      })}
    </section>
  );
}

export function SoFarTab({ p }: { p: StoryProject }) {
  const blocks = soFarBlocks(p);
  if (blocks.length === 0) {
    return (
      <EmptyState testid="lore-empty-sofar" title="Nothing written yet"
        detail="Each sequence gets a summary once its scenes are written." />
    );
  }
  return (
    <div className="s-col" style={{ gap: 10 }} data-testid="lore-sofar">
      {blocks.map((b) => (
        <section key={b.key} className="s-card">
          <div className="s-seq-title">{b.heading}</div>
          {b.summary && <p className="s-prose sm">{b.summary}</p>}
          {b.lines.map((line, i) => <div key={i} className="s-muted s-body">{line}</div>)}
        </section>
      ))}
    </div>
  );
}
