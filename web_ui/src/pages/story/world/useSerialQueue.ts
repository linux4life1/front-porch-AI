// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Runs a page's writes one after another. Leaving a text box saves it while a
// tap on the next control is already on its way; two writes in flight can land
// in either order and one silently undoes the other. A job's failure rejects
// its own promise and never blocks the jobs behind it.

import { useCallback, useRef } from 'react';

export function useSerialQueue(): <T>(job: () => Promise<T>) => Promise<T> {
  const tail = useRef<Promise<unknown>>(Promise.resolve());
  return useCallback(<T,>(job: () => Promise<T>): Promise<T> => {
    const next = tail.current.then(job);
    tail.current = next.catch(() => undefined);
    return next;
  }, []);
}
