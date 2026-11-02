// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a chat model switch did to the Generation values ("Qwen3-30B writes
// with “Qwen precise”.") with Undo, as the desktop's toast. Only a notice
// that arrives while the page is open shows: one left over from before is
// old news.

import { useEffect, useRef, useState } from 'react';
import type { GenPresets } from './genPresets';

type Act = (action: string, body?: Record<string, unknown>) => Promise<GenPresets | null>;

/** The notice to show: newer than the one the page first saw. */
export function useFreshNotice(data: GenPresets | null) {
  const first = useRef<number | null>(null);
  if (data && first.current === null) first.current = data.notice?.id ?? 0;
  const notice = data?.notice ?? null;
  return notice && first.current !== null && notice.id > first.current ? notice : null;
}

/** Calls [onNotice] once for each notice that arrives while mounted: a
 *  switch wrote new values the page should show. */
export function useOnFreshNotice(
  data: GenPresets | null,
  onNotice: (data: GenPresets) => void,
) {
  const seen = useRef<number | null>(null);
  useEffect(() => {
    if (!data) return;
    const id = data.notice?.id ?? 0;
    if (seen.current === null || id <= seen.current) {
      seen.current = Math.max(seen.current ?? 0, id);
      return;
    }
    seen.current = id;
    onNotice(data);
  }, [data, onNotice]);
}

export function GenPresetToast({
  data,
  act,
  extra = '',
  onUndone,
}: {
  data: GenPresets | null;
  act: Act;
  /** Said after the host's sentence (the chat's own changes). */
  extra?: string;
  onUndone?: (next: GenPresets) => void;
}) {
  const notice = useFreshNotice(data);
  const [busy, setBusy] = useState(false);
  if (!notice) return null;
  return (
    <div className="chat-import-notice gp-toast" role="status" data-testid="gen-preset-toast">
      <p>
        {notice.message}
        {extra ? ` ${extra}` : ''}
      </p>
      <button
        type="button"
        className="link-btn"
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          const next = await act('undo', { id: notice.id });
          setBusy(false);
          if (next?.undone) onUndone?.(next);
        }}
      >
        Undo
      </button>
      <button
        type="button"
        className="link-btn"
        aria-label="Dismiss"
        onClick={() => void act('dismiss', { id: notice.id })}
      >
        ✕
      </button>
    </div>
  );
}
