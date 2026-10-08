// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Phone back-swipe dismiss for a same-URL sheet. Pushes one history marker
// (keeping whatever state the router already stored, so HashRouter does not
// leave the page) and treats the matching popstate as a close. Backdrop,
// Escape, and Close call requestDismiss(), which pops that marker.
//
// StrictMode runs the effect twice. The first pass's cleanup must not pop
// the entry the second pass still owns — the epoch check is that guard.

import { useCallback, useEffect, useRef } from 'react';

const MARKER = 'open';

const epochs = new Map<string, number>();

function historyBase(): Record<string, unknown> {
  const state = window.history.state as Record<string, unknown> | null;
  return state !== null && typeof state === 'object' ? { ...state } : {};
}

function bumpEpoch(key: string): number {
  const next = (epochs.get(key) ?? 0) + 1;
  epochs.set(key, next);
  return next;
}

/**
 * [allowDismiss] returns false to keep the sheet open (the marker is
 * re-pushed on a back gesture, and a button dismiss is ignored). Message
 * edit uses it for the unsaved-changes confirm.
 */
export function useBackDismiss(
  markerKey: string,
  onDismiss: () => void,
  allowDismiss?: () => boolean,
): () => void {
  const onDismissRef = useRef(onDismiss);
  const allowRef = useRef(allowDismiss);
  onDismissRef.current = onDismiss;
  allowRef.current = allowDismiss;
  const popRef = useRef<() => void>(() => {});

  useEffect(() => {
    const mine = bumpEpoch(markerKey);
    let ignorePop = false;
    let pushed = false;

    const markerOpen = () => historyBase()[markerKey] === MARKER;

    const pushMarker = () => {
      window.history.pushState({ ...historyBase(), [markerKey]: MARKER }, '');
      pushed = true;
    };
    const popMarker = () => {
      if (!pushed || !markerOpen()) {
        pushed = false;
        return;
      }
      pushed = false;
      ignorePop = true;
      window.history.back();
    };

    if (markerOpen()) pushed = true;
    else pushMarker();

    const onPop = () => {
      if (ignorePop) {
        ignorePop = false;
        return;
      }
      pushed = false;
      const allow = allowRef.current;
      if (allow && !allow()) {
        pushMarker();
        return;
      }
      onDismissRef.current();
    };
    window.addEventListener('popstate', onPop);
    popRef.current = popMarker;

    return () => {
      window.removeEventListener('popstate', onPop);
      popRef.current = () => {};
      queueMicrotask(() => {
        if (epochs.get(markerKey) !== mine) return;
        popMarker();
      });
    };
  }, [markerKey]);

  return useCallback(() => {
    const allow = allowRef.current;
    if (allow && !allow()) return;
    popRef.current();
    onDismissRef.current();
  }, []);
}
