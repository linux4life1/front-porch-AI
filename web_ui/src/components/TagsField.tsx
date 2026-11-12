// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The tag control of the character editor: the label, the tags as removable
// chips and the "Add a tag..." field (the desktop EditorTagsField).

import { useState } from 'react';

export function TagsField({
  tags,
  onChange,
  showLabel = true,
}: {
  tags: string[];
  onChange: (tags: string[]) => void;
  showLabel?: boolean;
}) {
  const [text, setText] = useState('');
  const add = () => {
    const t = text.trim().toLowerCase();
    if (t && !tags.includes(t)) onChange([...tags, t]);
    setText('');
  };
  return (
    <div className="tags-field" data-testid="tags-field">
      {showLabel && <span className="field-label">Tags</span>}
      {tags.length > 0 && (
        <div className="tool-row">
          {tags.map((t) => (
            <button
              key={t}
              type="button"
              className="small"
              aria-label={`Remove tag ${t}`}
              onClick={() => onChange(tags.filter((x) => x !== t))}
            >
              {t} ✕
            </button>
          ))}
        </div>
      )}
      <div className="row-actions">
        <input
          placeholder="Add a tag..."
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              add();
            }
          }}
        />
        <button type="button" className="ghost" aria-label="Add tag" title="Add tag" onClick={add}>
          +
        </button>
      </div>
    </div>
  );
}
