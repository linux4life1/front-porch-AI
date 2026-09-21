export function applyTranscriptAutoScroll(
  el: {
    scrollTop: number;
    scrollHeight: number;
    scrollTo?: (init: ScrollToOptions) => void;
  } | null,
  ownedTop?: number | null,
): void {
  // Option B: never pin to scrollHeight. If a stream tick, overflow-anchor,
  // or a live-region update moved the viewport, put the user's offset back.
  if (!el || ownedTop == null) return;
  if (el.scrollTop !== ownedTop) el.scrollTop = ownedTop;
}
