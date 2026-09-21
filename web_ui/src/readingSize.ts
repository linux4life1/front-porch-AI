// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web-local reading size — the WebUI mirror of desktop StorageService.textScale.
// Stored per-device in localStorage and applied as --reading-size on :root so
// chat bubbles, the composer, the edit modal, and sidebar help scale together.
// Chrome (nav, chips, icon labels) is left alone.

export const READING_SIZE_MIN = 0.7;
export const READING_SIZE_MAX = 2.0;
export const READING_SIZE_DEFAULT = 1.0;

const KEY = 'fpai.readingSize';
const VAR = '--reading-size';

function clamp(n: number): number {
  if (!Number.isFinite(n)) return READING_SIZE_DEFAULT;
  return Math.min(READING_SIZE_MAX, Math.max(READING_SIZE_MIN, n));
}

export function loadReadingSize(): number {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw != null && raw !== '') return clamp(Number(raw));
  } catch {
    /* corrupt/absent — fall through to default */
  }
  return READING_SIZE_DEFAULT;
}

export function saveReadingSize(n: number): void {
  try {
    localStorage.setItem(KEY, String(clamp(n)));
  } catch {
    /* storage full / disabled — size just won't persist */
  }
}

/** Push the scale onto :root as --reading-size (consumed by styles.css). */
export function applyReadingSize(n: number): void {
  document.documentElement.style.setProperty(VAR, String(clamp(n)));
}
