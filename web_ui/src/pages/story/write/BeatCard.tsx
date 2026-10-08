// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One beat of the scene (sketch O): its number, type and description, the ⋯
// menu, the quality chips, the continuity fix with Undo, and the prose. The beat
// being written streams in place with a cursor and the card turns amber.
// Web twin of _buildBeatCard in story_writer_page.beats.dart.

import type { ContinuityFix, StoryBeat } from '../../../storyTypes';
import { Chip, MenuButton } from '../setup/primitives';
import { splitParagraphs } from '../paragraphs';
import { QualityChips } from './QualityChips';

export interface BeatActions {
  edit: () => void;
  write: () => void;
  rewrite: () => void;
  rewriteWithNote: () => void;
  copy: () => void;
  undoFix: () => void;
}

export function BeatCard({
  index, beat, text, fix, streaming, streamingText, running, banned, on,
}: {
  index: number;
  beat: StoryBeat;
  /** The beat's finished prose ('' until it is written). */
  text: string;
  fix?: ContinuityFix;
  /** This is the beat the pipeline is writing right now. */
  streaming: boolean;
  streamingText: string;
  running: boolean;
  banned: string[];
  on: BeatActions;
}) {
  return (
    <section className={`s-card${streaming ? ' sel' : ''}`} data-testid={`story-beat-${index}`}>
      <div className="s-row nowrap">
        <Chip>Beat {index + 1}</Chip>
        {beat.type && <Chip tone="honey">{beat.type}</Chip>}
        <span className="s-grow s-muted s-small s-clamp2">{beat.description}</span>
        {streaming ? (
          <Chip tone="amber">writing…</Chip>
        ) : (
          <MenuButton label={`Beat ${index + 1} menu`} testid={`story-beat-menu-${index}`} entries={[
            { label: 'Edit text by hand', disabled: !text, onSelect: on.edit },
            { label: text ? 'Rewrite' : 'Write', disabled: running, onSelect: text ? on.rewrite : on.write },
            { label: 'Rewrite with a note…', disabled: running || !text, onSelect: on.rewriteWithNote },
            { label: 'Copy', disabled: !text, onSelect: on.copy },
          ]} />
        )}
      </div>

      {text && <QualityChips text={text} banned={banned} />}

      {fix && (
        <div className="s-fix">
          <div className="s-row nowrap">
            <Chip tone="bad">Continuity: fixed</Chip>
            <span className="s-grow s-muted s-small">{fix.reason}</span>
            <button type="button" className="s-btn-ghost" data-testid={`story-undo-fix-${index}`} disabled={running}
              onClick={on.undoFix}>Undo fix</button>
          </div>
          {fix.edits.map((e, i) => (
            <p key={i} className="s-prose sm">
              <span className="s-del">{e.find}</span> <span className="s-ins">{e.replace}</span>
            </p>
          ))}
        </div>
      )}

      {streaming ? (
        <p className="s-prose s-pre s-cursor">{streamingText}</p>
      ) : text ? (
        <div className="s-prose">
          {splitParagraphs(text).map((para, i) => <p key={i} className="s-pre">{para}</p>)}
        </div>
      ) : beat.anchor ? (
        <span className="s-muted s-small" style={{ fontStyle: 'italic' }}>Anchor: {beat.anchor}</span>
      ) : null}
    </section>
  );
}
