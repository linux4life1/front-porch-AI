// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The studio switch on its own (no label beside it): a plan row's include
// toggle, or the one inside a labelled row. 34x19, amber when on, dimmed when
// it cannot be changed. The desktop's Switch.

export function Switch({ on, onChange, label, disabled, testid }: {
  on: boolean;
  onChange: (on: boolean) => void;
  /** What the switch controls, for a screen reader. */
  label: string;
  disabled?: boolean;
  testid?: string;
}) {
  return (
    <span className={`s-tog${on ? ' on' : ''}${disabled ? ' dis' : ''}`}>
      <input type="checkbox" checked={on} disabled={disabled} aria-label={label} data-testid={testid}
        onChange={(e) => onChange(e.target.checked)} />
    </span>
  );
}
