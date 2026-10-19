// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// ⌘F find-in-chat state for the web chat page (desktop parity via
// ChatFindController). Counts and navigation come from the Dart engine scan
// (`GET /api/chat/search`) — the request parks until the history backfill
// finishes, which is exactly the "waiting for older history" state, so the
// bar spins while it is in flight. Leaves paint the server's hit ranges
// through FindSurfaceContext; nothing re-matches the query client-side.

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import type { FindMessageHits, FindSurface } from '../../components/chatSearch';

export type FindHit = {
  messageIndex: number;
  region: number; // 0 = body, 1 = sender (engine constants)
  occurrence: number;
  start: number;
  end: number;
};

type SearchResponse = {
  bad: boolean;
  stale: boolean;
  capped: boolean;
  /** A regex scan ran past the engine's timeout and was abandoned. */
  slow?: boolean;
  matches: FindHit[];
};

export function useChatFind(opts: {
  sessionId?: string | null;
  /** Message indexes whose sender label is on screen; other sender hits are dropped. */
  senderLabelShown?: ReadonlySet<number>;
  /** Cheap transcript fingerprint; a change re-runs the (debounced) scan. */
  transcriptVersion: string;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [regexOn, setRegexOn] = useState(false);
  const [caseOn, setCaseOn] = useState(false);
  const [hits, setHits] = useState<FindHit[]>([]);
  const [active, setActive] = useState(-1);
  const [bad, setBad] = useState(false);
  const [slow, setSlow] = useState(false);
  const [waiting, setWaiting] = useState(false);
  const [reveal, setReveal] = useState<{ index: number; tick: number } | null>(null);
  const { transcriptVersion } = opts;
  const senderShown = useRef(opts.senderLabelShown);
  senderShown.current = opts.senderLabelShown;
  const seq = useRef(0);
  const tick = useRef(0);
  // Query + modes of the hits on screen. A re-scan for the same key was a
  // transcript change (a new reply, an edit): keep the reader's place
  // instead of jumping back to the first match.
  const shownKey = useRef<string | null>(null);

  const close = useCallback(() => {
    seq.current += 1;
    shownKey.current = null;
    setOpen(false);
    setHits([]);
    setActive(-1);
    setBad(false);
    setSlow(false);
    setWaiting(false);
    setReveal(null);
  }, []);

  const scan = useCallback(async () => {
    if (!open) return;
    void transcriptVersion; // re-created identity is the re-scan trigger
    const q = query.trim();
    const my = (seq.current += 1);
    if (!q) {
      shownKey.current = null;
      setHits([]);
      setActive(-1);
      setBad(false);
      setSlow(false);
      setWaiting(false);
      return;
    }
    setWaiting(true);
    try {
      const r = await api.get<SearchResponse>(
        `/api/chat/search?q=${encodeURIComponent(q)}` +
          (regexOn ? '&regex=1' : '') +
          (caseOn ? '&case=1' : ''),
      );
      if (my !== seq.current || !open) return;
      if (r.stale) {
        // Session/epoch moved under the scan — try once more against the
        // new transcript (the same conversation reopen settles on).
        void scan();
        return;
      }
      setBad(r.bad);
      setSlow(!!r.slow);
      if (r.bad || r.slow) {
        shownKey.current = null;
        setWaiting(false);
        setHits([]);
        setActive(-1);
        return;
      }
      const key = `${q}|${regexOn}|${caseOn}`;
      const fresh = shownKey.current !== key;
      shownKey.current = key;
      // Count only what can light up: the 1:1 web transcript (and user rows)
      // draws no speaker label, so its sender hits would be invisible stops.
      const labels = senderShown.current;
      const matches = r.matches.filter((h) => h.region !== 1 || !!labels?.has(h.messageIndex));
      setWaiting(false);
      setHits(matches);
      if (fresh) {
        const nextActive = matches.length ? 0 : -1;
        setActive(nextActive);
        if (nextActive >= 0) setReveal({ index: matches[nextActive].messageIndex, tick: (tick.current += 1) });
      } else {
        setActive((a) => (matches.length ? Math.min(Math.max(a, 0), matches.length - 1) : -1));
      }
    } catch {
      if (my === seq.current) setWaiting(false);
    }
  }, [open, query, regexOn, caseOn, transcriptVersion]);

  // Debounced scan on every query/mode/transcript change while open.
  useEffect(() => {
    if (!open) return;
    const t = setTimeout(() => void scan(), 150);
    return () => clearTimeout(t);
  }, [open, scan]);

  // Find belongs to the session it scanned — a switch closes it.
  useEffect(() => {
    close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opts.sessionId]);

  // Global ⌘F / Ctrl+F — suppress the browser's own find (it only sees the
  // mounted span; ours searches the whole archive).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') {
        e.preventDefault();
        setOpen(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const step = useCallback(
    (dir: number) => {
      if (!hits.length) return;
      const next = (active + dir + hits.length) % hits.length;
      setActive(next);
      setReveal({ index: hits[next].messageIndex, tick: (tick.current += 1) });
    },
    [hits, active],
  );

  const surface: FindSurface | null = useMemo(() => {
    if (!open || !query.trim() || bad || slow || !hits.length) return null;
    const byMessage = new Map<number, FindMessageHits>();
    for (const h of hits) {
      let entry = byMessage.get(h.messageIndex);
      if (!entry) byMessage.set(h.messageIndex, (entry = { body: [], sender: [] }));
      (h.region === 1 ? entry.sender : entry.body).push([h.start, h.end]);
    }
    const hit = active >= 0 && active < hits.length ? hits[active] : null;
    return {
      byMessage,
      active: hit
        ? { messageIndex: hit.messageIndex, region: hit.region === 1 ? 'sender' : 'body', start: hit.start }
        : null,
    };
  }, [open, query, bad, slow, active, hits]);

  const counter = hits.length
    ? `${active + 1} / ${hits.length >= 999 ? '999+' : hits.length}`
    : 'No matches';

  return {
    open,
    query,
    setQuery,
    regexOn,
    toggleRegex: () => setRegexOn((v) => !v),
    caseOn,
    toggleCase: () => setCaseOn((v) => !v),
    bad,
    slow,
    waiting,
    hits,
    counter,
    wildcardChip: !regexOn && query.includes('*'),
    step,
    close,
    surface,
    reveal,
  };
}
