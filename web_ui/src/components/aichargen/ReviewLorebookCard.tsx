// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's Lorebook card (desktop review_lorebook_section.dart): the
// first three entries, "and N more", and "Open the lorebook editor" which
// expands every entry with its keep checkbox (an unchecked entry is left out
// when the card is saved). Any row opens the entry dialog; a hand-edited entry
// says so and survives "Rewrite the lorebook".

import { ReviewRewriteCard } from './ReviewRewriteCard';
import type { LoreEntry } from '../LoreEntriesEditor';

export function ReviewLorebookCard({
  entries,
  handEdited,
  kept,
  open,
  onOpenChange,
  onToggle,
  onEdit,
  writing,
  locked,
  error,
  onRewrite,
  onStop,
}: {
  entries: LoreEntry[];
  /** Index-aligned with [entries]; true when the entry was edited by hand. */
  handEdited: boolean[];
  /** Index-aligned keep list; false leaves the entry out of the save. */
  kept: boolean[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onToggle: (index: number, keep: boolean) => void;
  onEdit: (index: number) => void;
  writing: boolean;
  locked: boolean;
  error?: string;
  onRewrite: (direction: string) => void;
  onStop: () => void;
}) {
  const shown = open ? entries.length : Math.min(3, entries.length);
  const more = entries.length - shown;
  return (
    <ReviewRewriteCard
      title="Lorebook"
      subtitle={`${entries.length} ${entries.length === 1 ? 'entry' : 'entries'}`}
      headAction={
        <button
          type="button"
          className="cg-p-text-btn"
          disabled={writing}
          onClick={() => onOpenChange(!open)}
        >
          Open the lorebook editor
        </button>
      }
      placeholder="Steer it (optional), e.g. more about the town, less about the sea"
      button="Rewrite the lorebook"
      caption="Rewrites the entries from the profile and your direction. An entry you edited by hand is kept."
      writing={writing}
      locked={locked}
      error={error}
      onRewrite={onRewrite}
      onStop={onStop}
    >
      <div className={`cg-lore-rows${writing ? ' writing' : ''}`}>
        {entries.slice(0, shown).map((entry, i) => (
          <div className="cg-lore-row" key={`${entry.name}-${i}`}>
            {open && (
              <input
                type="checkbox"
                className="cg-lore-keep"
                aria-label={`Keep ${entry.name || 'entry'}`}
                checked={kept[i] !== false}
                disabled={writing}
                onChange={(e) => onToggle(i, e.target.checked)}
              />
            )}
            <button
              type="button"
              className="cg-lore-open"
              title="Edit this entry"
              disabled={writing}
              onClick={() => onEdit(i)}
            >
              <span className="cg-lore-name">{entry.name || 'Untitled'}</span>
              <span className="cg-lore-preview">{entry.content}</span>
              {handEdited[i] && <span className="cg-lore-pill">Edited by hand</span>}
            </button>
          </div>
        ))}
        {more > 0 && <span className="cg-lore-more">and {more} more</span>}
      </div>
    </ReviewRewriteCard>
  );
}
