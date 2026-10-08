// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '../../../api/client';
import { cancelPack, fetchPack, onPackChanged, type PackView } from './packApi';

/** A line above the desk while a pack is being made, with a way to stop it. */
export function PackBanner() {
  const [pack, setPack] = useState<PackView | null>(null);
  const [stopped, setStopped] = useState(false);
  const [problem, setProblem] = useState('');
  const live = useRef(true);

  const load = useCallback(() => {
    fetchPack()
      .then((view) => {
        if (live.current) setPack(view);
      })
      .catch((e: unknown) => {
        if (live.current && e instanceof ApiError && e.status === 404) setPack(null);
      });
  }, []);

  // Looked at once, and again when this phone changes the pack. Only a pack
  // that is running is asked about again and again.
  useEffect(() => {
    live.current = true;
    load();
    const off = onPackChanged(load);
    return () => {
      live.current = false;
      off();
    };
  }, [load]);

  const running = pack?.running === true;
  useEffect(() => {
    if (!running) return;
    setStopped(false);
    setProblem('');
    const timer = window.setInterval(load, 3000);
    return () => window.clearInterval(timer);
  }, [running, load]);

  const stop = () => {
    setProblem('');
    cancelPack()
      .then((view) => {
        if (!live.current) return;
        setPack(view);
        setStopped(true);
      })
      .catch((e: unknown) => {
        if (live.current) setProblem(e instanceof ApiError ? e.message : 'Could not stop the pack.');
      });
  };

  if (!pack || !running) {
    return stopped ? <p data-region="pack-banner">Pack stopped.</p> : null;
  }
  return (
    <p data-region="pack-banner">
      Expression pack for {pack.characterName}: {pack.done} of {pack.total} made.{' '}
      <button type="button" className="secondary" onClick={stop}>
        Cancel pack
      </button>
      {problem ? <span role="alert"> {problem}</span> : null}
    </p>
  );
}
