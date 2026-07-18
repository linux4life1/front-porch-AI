// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Radio-style option tiles with an explanatory subtitle per choice — mirrors the
// desktop setup wizard's prose-length / pace / dialogue / maturity selectors
// (bare <select>s on the old web dropped the descriptions). Single-select.

export function OptionTiles({
  label,
  options,
  value,
  onChange,
}: {
  label: string;
  options: Record<string, string>;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div>
      <p className="field-label">{label}</p>
      <div className="opt-tiles">
        {Object.entries(options).map(([val, desc]) => (
          <button
            key={val}
            type="button"
            className={`opt-tile${value === val ? ' on' : ''}`}
            aria-pressed={value === val}
            onClick={() => onChange(val)}
          >
            <span className="opt-title">{val}</span>
            <span className="opt-desc">{desc}</span>
          </button>
        ))}
      </div>
    </div>
  );
}
