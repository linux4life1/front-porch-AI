type TranscriptEl = {
  scrollTop: number;
  scrollHeight: number;
  clientHeight?: number;
  scrollTo?: (init: ScrollToOptions) => void;
};

export function applyTranscriptAutoScroll(
  _el: TranscriptEl | null,
  _ownedTop?: number | null,
): void {
  // Option B: the user scrolls. Do not rewrite scrollTop on stream ticks —
  // that restore fought the browser and jumped the page around.
}

/** Forward list: latest is the bottom. One-shot for open / session restore. */
export function pinTranscriptToLatest(el: TranscriptEl | null): void {
  if (!el) return;
  const top = el.scrollHeight;
  if (el.scrollTo) el.scrollTo({ top });
  else el.scrollTop = top;
}

/** Keep the same rows on screen when older history is prepended above. */
export function holdTranscriptAfterPrepend(
  el: TranscriptEl | null,
  prevHeight: number,
): void {
  if (!el) return;
  const grew = el.scrollHeight - prevHeight;
  if (grew > 0) el.scrollTop += grew;
}

export function transcriptTipKey(
  messages: { sender: string; text: string }[],
): string {
  const tip = messages.length > 0 ? messages[messages.length - 1] : undefined;
  return tip ? `${tip.sender}\0${tip.text}` : '';
}

/** The oldest row's key. A prepend changes it; an append never does. */
export function transcriptHeadKey(
  messages: { sender: string; text: string }[],
): string {
  const head = messages.length > 0 ? messages[0] : undefined;
  return head ? `${head.sender}\0${head.text}` : '';
}

/**
 * Same tip on a longer list reads as older rows above, unless the head is
 * known and unchanged: then the rows were added below, and the tip matches
 * only because the new last line repeats the old one.
 */
export function isTranscriptPrepend(args: {
  prevLen: number;
  prevTip: string;
  nextLen: number;
  nextTip: string;
  prevHead?: string;
  nextHead?: string;
}): boolean {
  return (
    args.nextLen > args.prevLen &&
    args.nextTip !== '' &&
    args.nextTip === args.prevTip &&
    (args.prevHead === undefined ||
      args.nextHead === undefined ||
      args.nextHead !== args.prevHead)
  );
}

/** Stick-if-at-bottom while a reply is streaming. applyTranscriptAutoScroll stays a no-op. */
export function followTranscriptWhileStreaming(
  el: TranscriptEl | null,
  args: {
    followEnabled: boolean;
    generating: boolean;
    previousHeight: number;
    slop?: number;
  },
): boolean {
  if (!el || !args.followEnabled || !args.generating) return false;
  const slop = args.slop ?? 64;
  const client = el.clientHeight ?? 0;
  const edge = client > 0 ? el.scrollTop + client : el.scrollTop;
  if (edge < args.previousHeight - slop) return false;
  pinTranscriptToLatest(el);
  return true;
}

export const DEFAULT_FOLLOW_STREAMING = true;

export function classifyTranscriptGrowth(args: {
  sessionId?: string | null;
  prevSession: string | null;
  prevLen: number;
  prevTip: string;
  nextLen: number;
  nextTip: string;
  prevHead?: string;
  nextHead?: string;
}): 'open' | 'prepend' | 'other' {
  if (args.nextLen <= 0) return 'other';
  if (args.prevLen <= 0) return 'open';
  if (args.sessionId != null && args.sessionId !== args.prevSession) {
    return 'open';
  }
  if (isTranscriptPrepend(args)) return 'prepend';
  return 'other';
}
