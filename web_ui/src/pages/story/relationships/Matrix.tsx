// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The relationship grid (sketch S), kept the size of its cells. Read a row as
// "how this person sees that one"; a tapped cell selects the pair. A feeling is
// coloured by trust: warm teal, low red, the rest honey. Web twin of
// RelationshipsSection._matrix.

import type { StoryRelationship } from '../../../storyTypes';
import { trustTone } from '../storyShape';
import { findPair, type Pair } from './relationshipEdits';

export function Matrix({ names, rels, selected, onSelect }: {
  names: string[];
  rels: StoryRelationship[];
  selected: Pair | null;
  onSelect: (pair: Pair) => void;
}) {
  return (
    <table className="s-mx" data-testid="relationship-matrix">
      <thead>
        <tr>
          <th><div className="s-mx-h" /></th>
          {names.map((n) => <th key={n} scope="col"><div className="s-mx-h" title={n}>{n}</div></th>)}
        </tr>
      </thead>
      <tbody>
        {names.map((from) => (
          <tr key={from}>
            <th scope="row"><div className="s-mx-h" title={from}>{from}</div></th>
            {names.map((to) => {
              if (from === to) return <td key={to} className="self" />;
              const r = findPair(rels, from, to);
              const feeling = r?.feeling ?? '';
              const on = selected?.from === from && selected?.to === to;
              const cls = [r && feeling ? trustTone(r.trust) : 'none', on ? 'sel' : ''].filter(Boolean).join(' ');
              return (
                <td key={to} className={cls}>
                  <button type="button" data-testid={`rel-${from}-${to}`} aria-pressed={on}
                    aria-label={`${from} sees ${to}: ${feeling || 'nothing recorded'}`}
                    onClick={() => onSelect({ from, to })}>
                    <b>{feeling || '—'}</b>
                    {r?.note && <span>{r.note}</span>}
                  </button>
                </td>
              );
            })}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
