// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared input primitives for the AI character creator steps: a labelled text
// field, a labelled textarea, a text field with tap-to-append suggestion chips
// (Guided mode), and single/multi chip selectors (Automated mode + output
// settings). Presentation-only; all styling via AppColors tokens in styles.css.

export function Field({
  label, value, onChange, placeholder, hint,
}: {
  label: string; value: string; onChange: (v: string) => void;
  placeholder?: string; hint?: string;
}) {
  return (
    <label className="cg-field">
      <span className="cg-field-label">{label}{hint && <span className="muted small"> {hint}</span>}</span>
      <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />
    </label>
  );
}

export function AreaField({
  label, value, onChange, placeholder, rows = 4,
}: {
  label: string; value: string; onChange: (v: string) => void;
  placeholder?: string; rows?: number;
}) {
  return (
    <label className="cg-field">
      <span className="cg-field-label">{label}</span>
      <textarea rows={rows} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />
    </label>
  );
}

/** Text field with suggestion chips that append to its value when tapped. */
export function ChipInput({
  label, value, onChange, suggestions, placeholder,
}: {
  label: string; value: string; onChange: (v: string) => void;
  suggestions: string[]; placeholder?: string;
}) {
  const append = (s: string) => onChange(value.trim() ? `${value.trim()}, ${s}` : s);
  return (
    <div className="cg-field">
      <span className="cg-field-label">{label}</span>
      <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />
      <div className="cg-chips">
        {suggestions.map((s) => (
          <button type="button" key={s} className="cg-chip" onClick={() => append(s)}>+ {s}</button>
        ))}
      </div>
    </div>
  );
}

/** Single-select chip row (click toggles; clicking the selected one clears it). */
export function ChipSelect({
  label, value, options, onChange,
}: {
  label: string; value: string; options: string[]; onChange: (v: string) => void;
}) {
  return (
    <div className="cg-field">
      <span className="cg-field-label">{label}</span>
      <div className="cg-chips">
        {options.map((o) => (
          <button
            type="button"
            key={o}
            className={`cg-chip${value === o ? ' on' : ''}`}
            onClick={() => onChange(value === o ? '' : o)}
          >
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}

/** Multi-select chip row backed by a string[]. */
export function MultiChipSelect({
  label, values, options, onChange,
}: {
  label: string; values: string[]; options: string[]; onChange: (v: string[]) => void;
}) {
  const toggle = (o: string) =>
    onChange(values.includes(o) ? values.filter((x) => x !== o) : [...values, o]);
  return (
    <div className="cg-field">
      <span className="cg-field-label">{label}</span>
      <div className="cg-chips">
        {options.map((o) => (
          <button
            type="button"
            key={o}
            className={`cg-chip${values.includes(o) ? ' on' : ''}`}
            onClick={() => toggle(o)}
          >
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}
