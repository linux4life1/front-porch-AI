// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The band a sidebar needs bar's colour follows (docs/design/needs-on-the-clock.md,
// "Bands"): amber from 40 down, red from 25 down. The web twin of the desktop
// NeedsBar.bandColorOf (lib/ui/widgets/needs_bar.dart), which reads the same
// two numbers from the engine's NeedsSimulation thresholds.
//
// Above the band the bar is 'ok', a calm fill: the web's default stat fill is
// already the porch amber, so a needs bar has to step off it for amber to mean
// "getting low".

export const NEED_URGENT_AT = 40;
export const NEED_CRITICAL_AT = 25;

export type NeedTone = 'ok' | 'warn' | 'danger';

export function needTone(value: number): NeedTone {
  if (value <= NEED_CRITICAL_AT) return 'danger';
  if (value <= NEED_URGENT_AT) return 'warn';
  return 'ok';
}
