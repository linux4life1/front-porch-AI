// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Write screen's own dialogs: Go to scene, edit a beat by hand, and the
// Phrases-to-avoid list. (Rewrite with a note and Your own lens are the
// shared FieldsDialog.) Same titles and notes as the desktop's showStoryDialog
// calls in story_writer_page.*.dart.

import { useState } from 'react';
import type { SceneRef } from '../storyShape';
import { Dialog } from '../setup/primitives';

const cancel = (onCancel: () => void) => (
  <button type="button" className="s-btn-ghost" onClick={onCancel}>Cancel</button>
);

export function GoToSceneDialog({ refs, labelOf, onPick, onCancel }: {
  refs: SceneRef[];
  labelOf: (ref: SceneRef) => string;
  onPick: (ref: SceneRef) => void;
  onCancel: () => void;
}) {
  return (
    <Dialog title="Go to scene" wide testid="story-goto-scene" onClose={onCancel} actions={cancel(onCancel)}>
      <div className="s-col" style={{ gap: 0 }}>
        {refs.map((ref) => (
          <button key={`${ref.act}-${ref.index}`} type="button" className="s-listrow" onClick={() => onPick(ref)}>
            <span className="s-mono" style={{ width: 44, flex: 'none' }}>{labelOf(ref)}</span>
            <span className="s-grow s-ell">{ref.scene.title}</span>
          </button>
        ))}
      </div>
    </Dialog>
  );
}

/** The beat's prose in a serif box, saved exactly as typed (trimmed). */
export function ByHandDialog({ beat, text, onSave, onCancel }: {
  beat: number;
  text: string;
  onSave: (text: string) => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(text);
  return (
    <Dialog title={`Beat ${beat + 1}`} onClose={onCancel} actions={(
      <>
        {cancel(onCancel)}
        <button type="button" className="s-btn-primary" data-testid="story-dialog-confirm" onClick={() => onSave(value.trim())}>Save</button>
      </>
    )}>
      <div className="s-wide-edit">
        <textarea className="s-textarea prose" rows={10} autoFocus aria-label={`Beat ${beat + 1} text`}
          data-testid="story-beat-text" value={value} onChange={(e) => setValue(e.target.value)} />
      </div>
    </Dialog>
  );
}

/** The writer's own phrases, one per line; the engine's are listed, not editable. */
export function PhrasesDialog({ own, auto, onSave, onCancel }: {
  own: string[];
  auto: string[];
  onSave: (text: string) => void;
  onCancel: () => void;
}) {
  const [value, setValue] = useState(own.join('\n'));
  return (
    <Dialog title="Phrases to avoid" wide onClose={onCancel} actions={(
      <>
        {cancel(onCancel)}
        <button type="button" className="s-btn-primary" data-testid="story-dialog-confirm" onClick={() => onSave(value)}>Save</button>
      </>
    )}>
      <div className="body">One per line. The engine adds its own as it notices repeats; yours stay for the whole story.</div>
      <textarea className="s-textarea" rows={5} autoFocus aria-label="Phrases to avoid, one per line"
        data-testid="story-banned-text" value={value} onChange={(e) => setValue(e.target.value)} />
      {auto.length > 0 && <div className="body">Noticed lately: {auto.join(', ')}</div>}
    </Dialog>
  );
}
