// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Studio-styled slider field with danger boundary highlighting, graphical
// default pip, end range labels, optional ⓘ explainer, and unconstrained
// numeric input.

import { useState } from 'react';

const formatEnd = (v: number, step: number): string =>
  step >= 1 ? v.toLocaleString('en-US') : v.toFixed(2);

const clampPct = (v: number, min: number, max: number): number =>
  max <= min ? 0 : Math.max(0, Math.min(100, ((v - min) / (max - min)) * 100));

function buildTrackGradient(
  valPct: number,
  dMinPct: number | undefined,
  dMaxPct: number | undefined,
): string {
  const dangerInactive = 'color-mix(in srgb, var(--danger) 35%, transparent)';
  const dangerActive = 'var(--danger)';

  if (dMaxPct !== undefined) {
    if (valPct <= dMaxPct) {
      return `linear-gradient(to right, var(--accent) 0%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) ${dMaxPct}%, ${dangerInactive} ${dMaxPct}%, ${dangerInactive} 100%)`;
    }
    return `linear-gradient(to right, var(--accent) 0%, var(--accent) ${dMaxPct}%, ${dangerActive} ${dMaxPct}%, ${dangerActive} ${valPct}%, ${dangerInactive} ${valPct}%, ${dangerInactive} 100%)`;
  }
  if (dMinPct !== undefined) {
    if (valPct >= dMinPct) {
      return `linear-gradient(to right, ${dangerInactive} 0%, ${dangerInactive} ${dMinPct}%, var(--accent) ${dMinPct}%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) 100%)`;
    }
    return `linear-gradient(to right, ${dangerActive} 0%, ${dangerActive} ${valPct}%, ${dangerInactive} ${valPct}%, ${dangerInactive} ${dMinPct}%, var(--border) ${dMinPct}%, var(--border) 100%)`;
  }
  return `linear-gradient(to right, var(--accent) 0%, var(--accent) ${valPct}%, var(--border) ${valPct}%, var(--border) 100%)`;
}

export function SliderField({
  label,
  value,
  step,
  min,
  max,
  onChange,
  disabled,
  reset,
  defaultVal,
  dangerMin,
  dangerMax,
  info,
  card,
}: {
  label: string;
  value: number;
  step: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
  disabled?: boolean;
  /** A ↺ beside the value (generation presets); its title says to what. */
  reset?: { title: string; onReset: () => void };
  defaultVal?: number;
  dangerMin?: number;
  dangerMax?: number;
  /** Plain-language explanation behind the ⓘ beside the label. */
  info?: string;
  /** Wraps the slider in a `.studio-slider-card` container when true. */
  card?: boolean;
}) {
  const [showInfo, setShowInfo] = useState(false);
  const valPct = clampPct(value, min, max);
  const dMaxPct = dangerMax !== undefined ? clampPct(dangerMax, min, max) : undefined;
  const dMinPct = dangerMin !== undefined ? clampPct(dangerMin, min, max) : undefined;
  const defaultPct = defaultVal !== undefined ? clampPct(defaultVal, min, max) : undefined;
  const trackGradient = buildTrackGradient(valPct, dMinPct, dMaxPct);

  const field = (
    <div className="slider-field">
      <div className="slider-head">
        <span className="slider-label">
          {label}
          {info && (
            <button
              type="button"
              className="slider-info"
              aria-label={`About ${label}`}
              aria-expanded={showInfo}
              title={info}
              onClick={() => setShowInfo((v) => !v)}
            >
              ⓘ
            </button>
          )}
        </span>
        <span className="slider-head-right">
          {reset && (
            <button
              type="button"
              className="slider-reset"
              title={reset.title}
              aria-label={`${label}: ${reset.title}`}
              onClick={reset.onReset}
            >
              ↺
            </button>
          )}
          <input
            type="number"
            className="slider-val"
            value={value}
            step={step}
            min={0}
            disabled={disabled}
            onChange={(e) => {
              const n = Number(e.target.value);
              if (Number.isFinite(n)) onChange(n);
            }}
          />
        </span>
      </div>
      <div className="slider-track-wrap">
        <input
          type="range"
          value={Math.max(min, Math.min(max, value))}
          step={step}
          min={min}
          max={max}
          disabled={disabled}
          style={{ background: trackGradient }}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        {defaultPct !== undefined && (
          <span
            className="slider-default-pip"
            style={{ left: `${defaultPct}%` }}
            aria-hidden="true"
          />
        )}
      </div>
      <div className="slider-ends" aria-hidden="true">
        <span>{formatEnd(min, step)}</span>
        <span>{formatEnd(max, step)}</span>
      </div>
      {info && showInfo && <p className="muted small slider-info-text">{info}</p>}
    </div>
  );

  return card ? <div className="studio-slider-card">{field}</div> : field;
}
