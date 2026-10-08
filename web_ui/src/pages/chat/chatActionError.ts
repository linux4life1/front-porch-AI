// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Plain-English reason a transcript action (regenerate, continue, swipe, edit,
// fork, delete, switch chat…) failed. These used to reject into nowhere, so a
// tap that the desktop refused simply did nothing on the phone.

import { ApiError } from '../../api/client';

/** `what` completes "Couldn't …", e.g. "save your edit". */
export function describeActionFailure(what: string, e: unknown): string {
  const lead = `Couldn't ${what}.`;
  if (e instanceof ApiError) {
    if (e.status === 401 || e.status === 403) {
      return `${lead} Your web session has expired — sign in again on this device.`;
    }
    if (e.status >= 500) {
      return `${lead} Front Porch AI ran into a problem on your computer (${e.message}). Check it is still running, then try again.`;
    }
    return `${lead} ${e.message}`;
  }
  return `${lead} Front Porch AI didn't answer — check the app is still open on your computer and this device is on the same network, then try again.`;
}
