// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Ask, then do": a studio confirm that lives in the page (never
// window.confirm). `ask(copy, then)` opens the warm dialog; Cancel closes it,
// the confirm button runs `then`. Render `dialog` anywhere in the page.

import { useCallback, useState, type ReactNode } from 'react';
import type { ConfirmCopy } from './confirmCopy';
import { ConfirmDialog } from './setup/primitives';

export function useConfirm(): { ask: (copy: ConfirmCopy, then: () => void) => void; dialog: ReactNode } {
  const [open, setOpen] = useState<{ copy: ConfirmCopy; then: () => void } | null>(null);
  const ask = useCallback((copy: ConfirmCopy, then: () => void) => setOpen({ copy, then }), []);
  const dialog = open && (
    <ConfirmDialog
      title={open.copy.title}
      body={open.copy.body}
      confirmLabel={open.copy.confirmLabel}
      destructive={open.copy.destructive}
      onCancel={() => setOpen(null)}
      onConfirm={() => { const { then } = open; setOpen(null); then(); }}
    />
  );
  return { ask, dialog };
}
