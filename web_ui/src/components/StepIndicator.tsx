// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Horizontal step indicator (dots + labels + connecting lines) mirroring the
// Flutter wizards' AppBar pattern (create_character_page.dart) so the web
// "Create X" flows feel identical. Linear progression; completed steps are
// clickable to jump back.

export function StepIndicator({
  steps,
  current,
  onJump,
}: {
  steps: string[];
  current: number;
  onJump?: (i: number) => void;
}) {
  return (
    <div className="step-indicator">
      {steps.map((label, i) => (
        <div key={label} className="step-seg">
          {i > 0 && <span className={`step-line${i <= current ? ' done' : ''}`} />}
          <button
            type="button"
            className={`step-dot${i === current ? ' current' : ''}${i < current ? ' done' : ''}`}
            disabled={!onJump || i > current}
            onClick={() => onJump?.(i)}
            aria-current={i === current ? 'step' : undefined}
          >
            <span className="step-num">{i < current ? '✓' : i + 1}</span>
            <span className="step-label">{label}</span>
          </button>
        </div>
      ))}
    </div>
  );
}
