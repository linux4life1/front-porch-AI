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

// The server sends the engine's two numbers with every realism payload
// (`needsUrgentAt` / `needsCriticalAt`); the constants are the fallback for
// a payload that predates them.
export function needTone(
  value: number,
  urgentAt: number = NEED_URGENT_AT,
  criticalAt: number = NEED_CRITICAL_AT,
): NeedTone {
  if (value <= criticalAt) return 'danger';
  if (value <= urgentAt) return 'warn';
  return 'ok';
}
