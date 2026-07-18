// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared form primitives for the Realism/Needs sections (and reused by the
// character create/edit wizards). Presentation-only; all colors come from CSS
// tokens in styles.css so the desktop and phone shells stay consistent.

/** Labelled slider with an optional right-aligned tier/value badge. */
export function Slider({
  label,
  min,
  max,
  value,
  onChange,
  badge,
  step = 1,
}: {
  label: string;
  min: number;
  max: number;
  value: number;
  onChange: (v: number) => void;
  badge?: string;
  step?: number;
}) {
  return (
    <div className="realism-slider">
      <div className="realism-slider-head">
        <span>{label}</span>
        {badge !== undefined && <span className="realism-badge">{badge}</span>}
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseInt(e.target.value, 10))}
      />
    </div>
  );
}

/** On/off switch with an optional descriptive subtitle. */
export function ToggleRow({
  label,
  hint,
  value,
  onChange,
}: {
  label: string;
  hint?: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="realism-toggle">
      <span className="realism-toggle-text">
        <span>{label}</span>
        {hint && <small>{hint}</small>}
      </span>
      <input type="checkbox" checked={value} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

/** Labelled dropdown. */
export function SelectRow({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (v: string) => void;
}) {
  return (
    <label className="realism-field">
      <span>{label}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)}>
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

/** Color-coded approximate token-count badge. Mirrors the desktop create/edit
 *  counter exactly (edit_character_page.dart _updateTokenCount + _buildTokenBadge):
 *  tokens = ceil(chars / 4); blue/ok under 2k, amber/warn under 4k, red beyond. */
export function TokenBadge({ chars }: { chars: number }) {
  const tokens = Math.ceil(chars / 4);
  const tone = tokens > 4000 ? 'danger' : tokens > 2000 ? 'warn' : 'ok';
  return <span className={`token-badge ${tone}`}>~{tokens.toLocaleString()} tokens</span>;
}
