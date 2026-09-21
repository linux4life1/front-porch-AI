export function applyTranscriptAutoScroll(
  _el: {
    scrollTop: number;
    scrollHeight: number;
    scrollTo?: (init: ScrollToOptions) => void;
  } | null,
  _ownedTop?: number | null,
): void {
  // Option B: the user scrolls. Do not rewrite scrollTop on stream ticks —
  // that restore fought the browser and jumped the page around.
}
