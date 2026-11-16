// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One group of the desktop's Voice & Media tab, as the desktop paints it
// (voice_media_tab.dart and its sections): an accent section header, then a
// rounded card whose first row is an icon, a bold title with a muted line
// under it, and the trailing control. Sub-controls sit under a hairline
// inside the same card. `VoiceMediaSubRow` is one of those: a small muted
// icon, the label, the control at the right end.

import type { ReactNode } from 'react';

export function VoiceMediaCard({
  heading,
  icon,
  title,
  subtitle,
  control,
  iconTone = 'accent',
  testid,
  children,
}: {
  heading: string;
  icon: ReactNode;
  title: string;
  subtitle?: ReactNode;
  control?: ReactNode;
  /** `off` is the desktop's tertiary icon colour for a switched-off card. */
  iconTone?: 'accent' | 'off' | 'photo';
  testid?: string;
  /** Rows under the hairline; nothing (and no hairline) when absent. */
  children?: ReactNode;
}) {
  return (
    <div className="settings-group vm-group" data-testid={testid}>
      <h4 className="settings-group-heading">{heading}</h4>
      <div className="vm-card">
        <div className="vm-card-head">
          <span className={`vm-card-icon ${iconTone}`}>{icon}</span>
          <div className="vm-card-text">
            <span className="vm-card-title">{title}</span>
            {subtitle && <span className="vm-card-subtitle">{subtitle}</span>}
          </div>
          {control && <div className="vm-card-control">{control}</div>}
        </div>
        {children && <div className="vm-card-body">{children}</div>}
      </div>
    </div>
  );
}

export function VoiceMediaSubRow({
  icon,
  label,
  fill = false,
  strong = false,
  children,
}: {
  icon?: ReactNode;
  label: ReactNode;
  /** The control takes the rest of the row (the desktop's Expanded
   *  dropdowns); otherwise the label does and the control hugs the end. */
  fill?: boolean;
  /** The desktop's Auto-send row: a 13px primary label and amber icon,
   *  where the other sub-rows are 12px and muted. */
  strong?: boolean;
  children?: ReactNode;
}) {
  return (
    <div className={`vm-subrow${fill ? ' fill' : ''}${strong ? ' strong' : ''}`}>
      {icon && <span className="vm-subrow-icon">{icon}</span>}
      <span className="vm-subrow-label">{label}</span>
      {children && <div className="vm-subrow-control">{children}</div>}
    </div>
  );
}
