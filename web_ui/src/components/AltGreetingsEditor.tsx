// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared alternate-greetings list editor used by the character create wizard
// and the character edit page so both author and revise the greeting cycler
// identically. The chat greeting picker cycles through firstMessage + these.

export function AltGreetingsEditor({
  greetings,
  onChange,
}: {
  greetings: string[];
  onChange: (next: string[]) => void;
}) {
  return (
    <>
      <div className="row-label">
        <span>Alternate greetings</span>
        <button className="ghost" onClick={() => onChange([...greetings, ''])}>
          + Add
        </button>
      </div>
      {greetings.length === 0 && (
        <p className="muted small">
          None. Add openings the reader can cycle through on the first message.
        </p>
      )}
      {greetings.map((g, i) => (
        <div className="tool-row" key={i}>
          <textarea
            rows={3}
            value={g}
            onChange={(e) => {
              const next = [...greetings];
              next[i] = e.target.value;
              onChange(next);
            }}
          />
          <button
            className="icon-btn"
            title="Remove"
            onClick={() => onChange(greetings.filter((_, j) => j !== i))}
          >
            🗑
          </button>
        </div>
      ))}
    </>
  );
}
