// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Writing lens for this scene": every lens (the built-in ones and the story's
// own) with its mark, name and when to use it; the scene's current one is
// raised. "Add your own lens" opens the three-field dialog. Web twin of
// _changeLens / _addCustomLens in story_writer_page.lenses.dart.

import type { StoryLens } from '../../../storyTypes';
import { Dialog } from '../setup/primitives';
import { FieldsDialog } from '../FieldsDialog';
import { LensMark } from '../structure/LensParts';
import type { CustomLens } from './writeShape';

export function LensDialog({ lenses, current, onPick, onAdd, onCancel }: {
  lenses: StoryLens[];
  /** The scene's lens id, already normalised. */
  current: string;
  onPick: (lensId: string) => void;
  onAdd: () => void;
  onCancel: () => void;
}) {
  return (
    <Dialog title="Writing lens for this scene" wide testid="story-lens-dialog" onClose={onCancel} actions={(
      <>
        <button type="button" className="s-btn-ghost" data-testid="story-lens-add" onClick={onAdd}>Add your own lens</button>
        <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
      </>
    )}>
      <div className="s-col" style={{ gap: 2 }}>
        {lenses.map((l) => (
          <button key={l.id} type="button" className={`s-listrow${l.id === current ? ' on' : ''}`}
            data-testid={`story-lens-${l.id}`} aria-pressed={l.id === current} onClick={() => onPick(l.id)}>
            <LensMark lensId={l.id} lenses={lenses} />
            <span className="s-grow"><b>{l.name}</b>{' '}<span className="s-muted s-small">{l.context}</span></span>
          </button>
        ))}
      </div>
    </Dialog>
  );
}

/** A lens of the writer's own: a name, when to use it, how to write in it. */
export function CustomLensDialog({ onSave, onCancel }: {
  onSave: (lens: Omit<CustomLens, 'id'>) => void;
  onCancel: () => void;
}) {
  return (
    <FieldsDialog title="Your own lens" wide confirmLabel="Save lens" required="name"
      fields={[
        { key: 'name', hint: 'Name', testid: 'story-lens-name' },
        { key: 'context', hint: 'When to use it (one line)', testid: 'story-lens-context' },
        {
          key: 'prompt', hint: 'How to write in it: sentence rhythm, what the narration notices, how people talk…',
          multiline: true, rows: 4, testid: 'story-lens-prompt',
        },
      ]}
      onSubmit={(v) => onSave({ name: v.name, context: v.context, prompt: v.prompt })}
      onCancel={onCancel} />
  );
}
