// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Leaving a page with unsaved edits used to throw them away without a word.
// While `dirty` is true this asks before the page is left by a link, the nav,
// browser back, navigate(), a reload or closing the tab. Same question as the
// desktop's UnsavedChangesGuard.

import {
  type ReactElement,
  useCallback,
  useContext,
  useEffect,
  useRef,
} from 'react';
import {
  type BlockerFunction,
  UNSAFE_DataRouterContext,
  UNSAFE_LocationContext,
  useBlocker,
} from 'react-router-dom';

export const UNSAVED_QUESTION =
  'Discard unsaved changes?\n\nYou have edits that have not been saved. If you leave now they will be lost.';

/** True when there is nothing to lose or the user chose to discard. */
export function confirmDiscard(dirty: boolean): boolean {
  return !dirty || window.confirm(UNSAVED_QUESTION);
}

function RouteBlocker({ shouldBlock }: { shouldBlock: BlockerFunction }) {
  const blocker = useBlocker(shouldBlock);
  useEffect(() => {
    if (blocker.state !== 'blocked') return;
    if (window.confirm(UNSAVED_QUESTION)) blocker.proceed();
    else blocker.reset();
  }, [blocker]);
  return null;
}

export interface UnsavedChanges {
  /** Render this somewhere in the page. */
  prompt: ReactElement | null;
  /**
   * Call right before a Save (or Create) navigates away: that leave writes
   * the edits, so it must not ask.
   */
  leaveWithoutAsking: () => void;
}

export function useUnsavedChanges(dirty: boolean): UnsavedChanges {
  const dirtyRef = useRef(dirty);
  dirtyRef.current = dirty;
  // Set by a Save that is about to leave. It holds until the page has moved
  // on or the user edits again: clearing it as soon as the save made the page
  // clean let a back() that leaves the document hit the unload prompt before
  // the listener was removed.
  const bypassRef = useRef(false);
  const locationKey = useContext(UNSAFE_LocationContext)?.location?.key;
  useEffect(() => {
    bypassRef.current = false;
  }, [locationKey]);
  const wasDirty = useRef(dirty);
  useEffect(() => {
    if (dirty && !wasDirty.current) bypassRef.current = false;
    wasDirty.current = dirty;
  }, [dirty]);

  useEffect(() => {
    if (!dirty) return;
    const onBeforeUnload = (e: BeforeUnloadEvent) => {
      if (bypassRef.current) return;
      e.preventDefault();
      // Older engines still need returnValue set to show the prompt.
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    return () => window.removeEventListener('beforeunload', onBeforeUnload);
  }, [dirty]);

  // Same-page history entries (a sheet's back-dismiss marker) are not a leave.
  const shouldBlock = useCallback<BlockerFunction>(
    ({ currentLocation, nextLocation }) =>
      dirtyRef.current &&
      !bypassRef.current &&
      (currentLocation.pathname !== nextLocation.pathname ||
        currentLocation.search !== nextLocation.search),
    [],
  );

  // Only a data router can block (unit tests mount pages in a MemoryRouter).
  const dataRouter = useContext(UNSAFE_DataRouterContext);
  const prompt = dataRouter ? <RouteBlocker shouldBlock={shouldBlock} /> : null;

  const leaveWithoutAsking = useCallback(() => {
    bypassRef.current = true;
  }, []);

  return { prompt, leaveWithoutAsking };
}

/**
 * For a modal over a page that has no Save-gated form of its own: while the
 * modal holds typed input, browser back, a nav link or a reload asks too,
 * not only its own close. A page that already calls useUnsavedChanges
 * should fold the modal's dirty flag into that call instead (a router runs
 * one blocker at a time).
 */
export function UnsavedPrompt({ dirty }: { dirty: boolean }) {
  return useUnsavedChanges(dirty).prompt;
}
