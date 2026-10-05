// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Who sets chat's context: the one rule the host keeps everywhere
// (koboldPresetOwnsContext in lib/services/kobold/kobold_context_owner.dart).
// The chosen preset does, while KoboldCpp is the backend and a preset is
// chosen. On another backend a preset left chosen is not read, so the context
// is the user's.

/** True when the chosen preset sets the context on `backend` (as the host
 * stores it: anything but `openRouter` and `omlx` is KoboldCpp). */
export function presetOwnsContext(backend: string, activeKcppsPath?: string | null): boolean {
  return backend !== 'openRouter' && backend !== 'omlx' && (activeKcppsPath ?? '').trim() !== '';
}
