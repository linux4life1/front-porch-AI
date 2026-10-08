// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Phrases to avoid": always shown, so a first phrase can be added to an empty
// list. The writer's own phrases stay for the whole story; the engine adds the
// ones it notices itself repeating. Web twin of _buildBannedCard in
// story_writer_page.lenses.dart.

import { Chip } from '../setup/primitives';
import { PHRASE_CHIPS, phrasesSummary } from './writeShape';

export function PhrasesCard({ own, auto, onEdit }: { own: string[]; auto: string[]; onEdit: () => void }) {
  const all = [...own, ...auto];
  return (
    <section className="s-card" data-testid="story-banned">
      <div className="s-row nowrap">
        <span className="s-key s-grow">Phrases to avoid</span>
        <button type="button" className="s-btn-ghost" data-testid="story-banned-edit" onClick={onEdit}>Edit list</button>
      </div>
      {all.length === 0 ? (
        <span className="s-muted s-small">
          None yet. The engine adds phrases it notices itself repeating; add your own with Edit list.
        </span>
      ) : (
        <>
          <div className="s-chips">
            {all.slice(0, PHRASE_CHIPS).map((phrase, i) => <Chip key={i}>“{phrase}”</Chip>)}
            {all.length > PHRASE_CHIPS && <Chip>+ {all.length - PHRASE_CHIPS} more</Chip>}
          </div>
          <span className="s-muted s-small">{phrasesSummary(own, auto)}</span>
        </>
      )}
    </section>
  );
}
