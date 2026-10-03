// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The app scrolls inside its own container (.app-main on a wide screen,
// .app-content on a phone), not the window. The scroll reader reads and writes
// the position of whichever ancestor actually scrolls.

/** The nearest ancestor that scrolls vertically; the page itself when none does. */
export function scrollParent(el: HTMLElement | null): HTMLElement | null {
  for (let node = el?.parentElement ?? null; node; node = node.parentElement) {
    const { overflowY } = getComputedStyle(node);
    if (overflowY === 'auto' || overflowY === 'scroll') return node;
  }
  return (document.scrollingElement as HTMLElement | null) ?? null;
}
