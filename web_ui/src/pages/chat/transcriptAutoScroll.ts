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

/** Follow the live reply. startOfStream jumps from mid-history; later tokens stick if at bottom. */
export function followTranscriptWhileStreaming(
  el: TranscriptEl | null,
  args: {
    followEnabled: boolean;
    generating: boolean;
    previousHeight: number;
    startOfStream?: boolean;
    slop?: number;
  },
): boolean {
  if (!el || !args.followEnabled || !args.generating) return false;
  const slop = args.slop ?? 64;
  const client = el.clientHeight ?? 0;
  const edge = client > 0 ? el.scrollTop + client : el.scrollTop;
  if (!args.startOfStream && edge < args.previousHeight - slop) return false;
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
}): 'open' | 'prepend' | 'other' {
  if (args.nextLen <= 0) return 'other';
  if (args.prevLen <= 0) return 'open';
  if (args.sessionId != null && args.sessionId !== args.prevSession) {
    return 'open';
  }
  if (
    args.nextLen > args.prevLen &&
    args.nextTip !== '' &&
    args.nextTip === args.prevTip
  ) {
    return 'prepend';
  }
  return 'other';
}
