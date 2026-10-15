// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The foot of the phone's Output step (docs/design/creator-ui-spec.md,
// Configure header): when the form was loaded from a template, the Started
// from pill and its caption; then Save as template, which opens the Save
// dialog.

import { useState } from 'react';
import type { ChargenForm } from './chargenForm';
import { BookmarkIcon } from './creatorIcons';
import { SaveTemplateSheet } from './TemplateSheets';
import type { CreatorTemplate, TemplateStart } from './templatesApi';

export function TemplateSaveBar({
  form,
  templates,
  startedFrom,
  onSaved,
}: {
  form: ChargenForm;
  /** Null until the relay's list has arrived: the sheet cannot refuse a
   *  built-in's name without it, so Save waits. */
  templates: CreatorTemplate[] | null;
  startedFrom: TemplateStart | null;
  onSaved: (to: TemplateStart) => void;
}) {
  const [open, setOpen] = useState(false);
  const ready = templates !== null;
  return (
    <div className="cg-tpl-save" data-testid="template-save">
      {startedFrom && (
        <div className="cg-tpl-started">
          <span className="cg-tpl-from">
            <BookmarkIcon size={14} />
            <span className="cg-tpl-from-name">Started from: {startedFrom.name}</span>
          </span>
          <span className="cg-tpl-from-caption">Changes stay on this form until you save them to the template.</span>
        </div>
      )}
      <button
        type="button"
        className="cg-tpl-save-btn"
        disabled={!ready}
        title={ready ? undefined : 'Loading the templates…'}
        onClick={() => setOpen(true)}
      >
        <BookmarkIcon size={18} />
        Save as template
      </button>
      {open && templates && (
        <SaveTemplateSheet
          form={form}
          templates={templates}
          startedFrom={startedFrom}
          onSaved={(to) => {
            setOpen(false);
            onSaved(to);
          }}
          onClose={() => setOpen(false)}
        />
      )}
    </div>
  );
}
