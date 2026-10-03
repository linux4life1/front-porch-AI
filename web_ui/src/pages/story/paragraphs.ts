// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Prose paragraphs break on blank lines, on the Write cards, in Scroll and in
// the book; a single line break stays inside its paragraph.

export function splitParagraphs(text: string): string[] {
  return text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);
}
