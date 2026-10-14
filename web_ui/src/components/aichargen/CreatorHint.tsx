// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's hint box (docs/design/creator-ui-spec.md, Hint box): an
// amber info icon, a title, a line of body, then an outlined action and a
// quiet second choice. The Greetings step raises it when the profile
// changed after the greetings were written.

import { InfoIcon } from './creatorIcons';

export function CreatorHint({
  title,
  body,
  action,
  onAction,
  dismiss,
  onDismiss,
  disabled = false,
}: {
  title: string;
  body: string;
  action: string;
  onAction: () => void;
  dismiss: string;
  onDismiss: () => void;
  disabled?: boolean;
}) {
  return (
    <section className="cg-hint" role="status" aria-label={title} data-testid="creator-hint">
      <span className="cg-hint-icon">
        <InfoIcon />
      </span>
      <div className="cg-hint-text">
        <h3>{title}</h3>
        <p>{body}</p>
        <div className="cg-hint-actions">
          <button type="button" className="cg-hint-action" disabled={disabled} onClick={onAction}>
            {action}
          </button>
          <button type="button" className="cg-hint-dismiss" disabled={disabled} onClick={onDismiss}>
            {dismiss}
          </button>
        </div>
      </div>
    </section>
  );
}
