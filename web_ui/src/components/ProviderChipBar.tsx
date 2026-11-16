// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop RemoteProviderBar twin: one wrapping row of host chips, the
// selected one accent-filled. Driven by the shared BACKEND_OPTIONS list so
// chat speech and Realism evals never disagree on which hosts exist or in
// what order they show. The caller filters visibility (oMLX on macOS only)
// and passes the disabled flag (Intel Mac cannot run KoboldCpp).

import { BACKEND_OPTIONS, type BackendOption } from '../backendOptions';

export function ProviderChipBar({
  selected,
  options = BACKEND_OPTIONS,
  onSelect,
  koboldDisabled = false,
  testId,
  ariaLabel = 'Provider',
}: {
  selected: string;
  /** Defaults to the full shared list; callers filter (oMLX availability). */
  options?: BackendOption[];
  onSelect: (id: string) => void;
  /** Intel Mac host: KoboldCpp shows greyed, exactly as the desktop bar. */
  koboldDisabled?: boolean;
  testId?: string;
  ariaLabel?: string;
}) {
  return (
    <div className="provider-chips" role="group" aria-label={ariaLabel} data-testid={testId}>
      {options.map((o) => (
        <button
          key={o.id}
          type="button"
          className={`provider-chip${o.id === selected ? ' chip-on' : ''}`}
          aria-pressed={o.id === selected}
          disabled={o.id === 'kobold' && koboldDisabled}
          data-testid={`provider-chip-${o.id}`}
          onClick={() => onSelect(o.id)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
