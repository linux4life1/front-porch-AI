// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Review step's Example dialogue card (desktop review_step.dart's
// `_dialogueCard`): the saved example dialogue, editable, with the steer line
// and Regenerate/Stop, and the full-screen editor behind the expand button.

import { useState } from 'react';
import { MacroField } from '../MacroField';
import { MacroText } from './macroText';
import { ReviewRewriteCard } from './ReviewRewriteCard';

export function ReviewDialogueCard({
  value,
  subtitle,
  writingText,
  writing,
  locked,
  error,
  onEdit,
  onRewrite,
  onStop,
}: {
  value: string;
  subtitle: string;
  /** The text streaming from the relay while it writes. */
  writingText: string;
  writing: boolean;
  locked: boolean;
  error?: string;
  onEdit: (next: string) => void;
  onRewrite: (direction: string) => void;
  onStop: () => void;
}) {
  const [full, setFull] = useState(false);
  return (
    <ReviewRewriteCard
      title="Example dialogue"
      subtitle={subtitle}
      headAction={
        <button
          type="button"
          className="icon-btn"
          title="Open Example dialogue in the full editor"
          aria-label="Open Example dialogue in the full editor"
          disabled={writing || locked}
          onClick={() => setFull(true)}
        >
          ⤢
        </button>
      }
      placeholder="Steer it (optional), e.g. shorter lines, more bite"
      button="Regenerate"
      writing={writing}
      locked={locked}
      error={error}
      onRewrite={onRewrite}
      onStop={onStop}
    >
      {writing ? (
        <div className="cg-g-stream" aria-live="polite">
          <MacroText text={writingText} />
          <span className="cg-g-caret" />
        </div>
      ) : (
        <MacroField
          label="Example dialogue"
          value={value}
          onChange={onEdit}
          rows={5}
          ariaLabel="Example dialogue text"
          showHead={false}
          full={full}
          onFullChange={setFull}
        />
      )}
    </ReviewRewriteCard>
  );
}
