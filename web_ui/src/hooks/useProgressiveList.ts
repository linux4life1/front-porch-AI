// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Render a long list in growing chunks so the DOM never mounts thousands of
// cards at once. The library grid loads the *whole* (search/folder/sort-scoped)
// character list in one request — now small and gzipped — but on a big library
// that's still thousands of card + <img> nodes, which is heavy to lay out and
// scroll on a phone. This caps the mounted nodes to what has actually been
// scrolled to, growing by a batch each time a bottom sentinel nears the
// viewport (an IntersectionObserver, so no scroll handler and no new
// dependency). Off-screen images are still deferred by loading="lazy".

import { useEffect, useRef, useState, type RefObject } from 'react';

const DEFAULT_BATCH = 60;

export interface ProgressiveList<T> {
  /** The slice to render right now. */
  visible: T[];
  /** Attach to a sentinel element placed just after the rendered list. */
  sentinelRef: RefObject<HTMLDivElement>;
  /** True while more items remain to be revealed. */
  hasMore: boolean;
}

export function useProgressiveList<T>(
  items: T[],
  batch: number = DEFAULT_BATCH,
): ProgressiveList<T> {
  const [count, setCount] = useState(batch);
  const sentinelRef = useRef<HTMLDivElement>(null);

  // A new result set (search / folder / sort change, or a live refetch replaces
  // the array) → start again from the first chunk.
  useEffect(() => {
    setCount(batch);
  }, [items, batch]);

  const hasMore = count < items.length;

  useEffect(() => {
    if (!hasMore) return;
    const el = sentinelRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          setCount((c) => Math.min(c + batch, items.length));
        }
      },
      // Pre-load a screenful early so scrolling feels seamless. Re-observing on
      // each `count` change re-checks the sentinel, so a tall viewport fills
      // itself instead of stalling on an already-visible sentinel.
      { rootMargin: '800px' },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [hasMore, batch, items, count]);

  return { visible: items.slice(0, count), sentinelRef, hasMore };
}
