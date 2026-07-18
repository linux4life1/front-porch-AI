// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CSS-columns pagination for the web book reader. The book content flows into a
// fixed-height multi-column box; each column is one "page". This measures the
// total page count, the per-page horizontal stride (for the flip transform), and
// the page index of every TOC anchor ([data-anchor] element). Recomputes on
// resize and whenever the content signature changes.
//
// A clean web reader — it does not pixel-match the Flutter CustomPageFlip, but
// gives real pagination, a two-margin paper page, prev/next, TOC jumps, and
// reading-progress as the desktop reader does.

import { useCallback, useEffect, useState, type RefObject } from 'react';

const GAP = 72; // column-gap; ≥ page side inset (36) so margins stay clean.

export interface BookLayout {
  totalPages: number;
  stride: number;
  anchors: Record<string, number>;
}

export function useBookPages(
  flowRef: RefObject<HTMLDivElement | null>,
  viewportRef: RefObject<HTMLDivElement | null>,
  signature: string,
) {
  const [layout, setLayout] = useState<BookLayout>({ totalPages: 1, stride: 1, anchors: {} });

  const remeasure = useCallback(() => {
    const flow = flowRef.current;
    if (!flow) return;
    // Column width = the flow's own inset content box; gap keeps margins clean.
    const fw = flow.clientWidth;
    if (fw <= 0) return;
    flow.style.columnWidth = `${fw}px`;
    flow.style.columnGap = `${GAP}px`;

    const stride = fw + GAP;
    const totalPages = Math.max(1, Math.round((flow.scrollWidth + GAP) / stride));

    const anchors: Record<string, number> = {};
    flow.querySelectorAll<HTMLElement>('[data-anchor]').forEach((el) => {
      const key = el.dataset.anchor;
      if (key) anchors[key] = Math.max(0, Math.round(el.offsetLeft / stride));
    });

    setLayout({ totalPages, stride, anchors });
  }, [flowRef]);

  // Remeasure after content renders / changes.
  useEffect(() => {
    const t = setTimeout(remeasure, 0);
    return () => clearTimeout(t);
  }, [remeasure, signature]);

  // Remeasure on viewport resize.
  useEffect(() => {
    const vp = viewportRef.current;
    if (!vp || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(() => remeasure());
    ro.observe(vp);
    return () => ro.disconnect();
  }, [viewportRef, remeasure]);

  return { ...layout, remeasure };
}
