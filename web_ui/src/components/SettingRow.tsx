// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One setting as the desktop paints it (lib/ui/settings/tabs): title with a
// muted explanation under it on the left, the control on the right, hairline
// divider below — no card outline. The web Settings rows are built from this
// so the page reads like the Dart window (one-chat-ux PR 7a); the switch
// visuals come from the `.switch` skin in styles/settings.css.

import type { ReactNode } from 'react';

export function SettingRow({
  title,
  blurb,
  children,
  testid,
}: {
  title: string;
  /** The muted line under the title; the desktop shows one for most rows. */
  blurb?: ReactNode;
  /** The control (switch, select, slider…) painted at the row's right end. */
  children?: ReactNode;
  testid?: string;
}) {
  return (
    <div className="setting-row" data-testid={testid}>
      <div className="setting-row-main">
        <span className="setting-row-title">{title}</span>
        {blurb && <p className="setting-row-blurb">{blurb}</p>}
      </div>
      {children && <div className="setting-row-control">{children}</div>}
    </div>
  );
}
