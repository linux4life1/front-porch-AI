// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// ⌘F find-in-chat state for the web chat page (desktop parity via
// ChatFindController). Counts and navigation come from the Dart engine scan
// (`GET /api/chat/search`) — the request parks until the history backfill
// finishes, which is exactly the "waiting for older history" state, so the
// bar spins while it is in flight. Leaves self-highlight locally through
// FindSurfaceContext (chatSearch.ts mirror).

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../../api/client';
import { compileFindQuery, type FindSurface } from '../../components/chatSearch';

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
  matches: FindHit[];
};

export function useChatFind(opts: {
  sessionId?: string | null;
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
  const [waiting, setWaiting] = useState(false);
  const [reveal, setReveal] = useState<{ index: number; tick: number } | null>(null);
  const { transcriptVersion } = opts;
  const seq = useRef(0);
  const tick = useRef(0);

  const close = useCallback(() => {
    seq.current += 1;
    setOpen(false);
    setHits([]);
    setActive(-1);
    setBad(false);
    setWaiting(false);
    setReveal(null);
  }, []);

  const scan = useCallback(async () => {
    if (!open) return;
    void transcriptVersion; // re-created identity is the re-scan trigger
    const q = query.trim();
    const my = (seq.current += 1);
    if (!q) {
      setHits([]);
      setActive(-1);
      setBad(false);
      setWaiting(false);
      return;
    }
    const spec = compileFindQuery(q, { regex: regexOn, caseSensitive: caseOn });
    setBad(spec.bad);
    if (spec.bad) {
      setHits([]);
      setActive(-1);
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
      setWaiting(false);
      setHits(r.matches);
      const nextActive = r.matches.length ? 0 : -1;
      setActive(nextActive);
      if (nextActive >= 0) setReveal({ index: r.matches[nextActive].messageIndex, tick: (tick.current += 1) });
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
    if (!open || !query.trim() || bad) return null;
    const hit = active >= 0 && active < hits.length ? hits[active] : null;
    return {
      spec: compileFindQuery(query, { regex: regexOn, caseSensitive: caseOn }),
      activeMessageIndex: hit ? hit.messageIndex : null,
      activeRegion: hit && hit.region === 1 ? 'sender' : 'body',
      activeOccurrence: hit ? hit.occurrence : -1,
    };
  }, [open, query, bad, active, hits, regexOn, caseOn]);

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
