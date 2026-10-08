// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The top line of an Overview card: the key label on the left, its one action
// (a ghost button) on the right.

import type { ReactNode } from 'react';

export function CardHead({ label, children }: { label: string; children?: ReactNode }) {
  return (
    <div className="s-row nowrap">
      <span className="s-key s-grow">{label}</span>
      {children}
    </div>
  );
}
