// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A one-line note that clears itself: the desktop's snackbar ("Added 3 lore
// entries.", "Nothing to undo: …"), shown inline in the page.

import { useEffect, useState } from 'react';

export function useNotice(ms = 4000): [string, (note: string) => void] {
  const [notice, setNotice] = useState('');
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(''), ms);
    return () => clearTimeout(timer);
  }, [notice, ms]);
  return [notice, setNotice];
}
