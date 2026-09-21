// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Reading size slider — web mirror of desktop General Settings / in-chat UI
// sheet. Same name, same range, same job: bubbles, composer, edit, sidebar help.

import { useState } from 'react';
import {
  READING_SIZE_MAX,
  READING_SIZE_MIN,
  applyReadingSize,
  loadReadingSize,
  saveReadingSize,
} from '../readingSize';

export function ReadingSizeSlider() {
  const [scale, setScale] = useState(loadReadingSize);

  const commit = (raw: number) => {
    setScale(raw);
    saveReadingSize(raw);
    applyReadingSize(raw);
  };

  return (
    <label className="reading-size-row">
      <span>Reading size</span>
      <input
        type="range"
        min={READING_SIZE_MIN}
        max={READING_SIZE_MAX}
        step={0.1}
        value={scale}
        onChange={(e) => commit(Number(e.target.value))}
        aria-valuemin={READING_SIZE_MIN}
        aria-valuemax={READING_SIZE_MAX}
        aria-valuenow={scale}
        aria-label="Reading size"
      />
      <span className="reading-size-value">{scale.toFixed(1)}×</span>
    </label>
  );
}

export function ReadingSizeSettings() {
  return (
    <section className="card">
      <h3>Reading size</h3>
      <p className="reading-blurb">
        Chat bubbles, the composer, message edit, and sidebar help. Buttons and
        labels stay put.
      </p>
      <ReadingSizeSlider />
    </section>
  );
}
