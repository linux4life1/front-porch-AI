// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Integrated Thinking Off + strength chips subcard for Generation settings.

import {
  reasoningEffortBlurb,
  reasoningEffortChipsFor,
  reasoningEffortDisplayedSelection,
  reasoningEffortMappingCaption,
  reasoningEffortTitle,
} from '../utils/reasoningEffort';

export function ThinkingSettingsControl({
  model,
  reasoningEnabled,
  reasoningEffort,
  reasoningMandatory,
  reasoningEfforts,
  reasoningLocalSupport,
  onPatch,
}: {
  model: string;
  reasoningEnabled: boolean;
  reasoningEffort: string;
  reasoningMandatory?: boolean;
  reasoningEfforts?: string[];
  reasoningLocalSupport?: string;
  onPatch: (p: Record<string, unknown>) => void;
}) {
  const thinkingOn = Boolean(reasoningEnabled) || Boolean(reasoningMandatory);
  const offLocked = Boolean(reasoningMandatory) || reasoningLocalSupport === 'none';
  const levelIds: string[] = reasoningEfforts?.length
    ? reasoningEfforts
    : reasoningLocalSupport
      ? []
      : reasoningEffortChipsFor(model);

  return (
    <div className="gen-subcard">
      <h4 className="gen-subcard-title">Thinking</h4>
      {/* Off and the strength levels are one control */}
      <div className="thinking-strength">
        <div className="thinking-strength-chips" role="group" aria-label="Thinking">
          <button
            type="button"
            className={`thinking-strength-chip${thinkingOn ? '' : ' on'}`}
            disabled={offLocked}
            aria-pressed={!thinkingOn}
            onClick={() => onPatch({ reasoningEnabled: false })}
          >
            <span className="thinking-strength-chip-title">Off</span>
            <span className="thinking-strength-chip-sub">No thinking</span>
          </button>
          {levelIds.map((id) => {
            const on =
              thinkingOn &&
              reasoningEffortDisplayedSelection(
                model,
                reasoningEffort || 'medium',
                reasoningEfforts?.length ? reasoningEfforts : undefined,
              ) === id;
            return (
              <button
                key={id}
                type="button"
                className={`thinking-strength-chip${on ? ' on' : ''}`}
                aria-pressed={on}
                onClick={() => onPatch({ reasoningEnabled: true, reasoningEffort: id })}
              >
                <span className="thinking-strength-chip-title">{reasoningEffortTitle(id)}</span>
                <span className="thinking-strength-chip-sub">{reasoningEffortBlurb(id)}</span>
              </button>
            );
          })}
          {levelIds.length === 0 && reasoningLocalSupport !== 'none' && (
            <button
              type="button"
              className={`thinking-strength-chip${thinkingOn ? ' on' : ''}`}
              aria-pressed={thinkingOn}
              onClick={() => onPatch({ reasoningEnabled: true })}
            >
              <span className="thinking-strength-chip-title">On</span>
              <span className="thinking-strength-chip-sub">Think before replying</span>
            </button>
          )}
        </div>
        {thinkingOn && levelIds.length > 0 && (
          <p className="muted small thinking-strength-caption">
            {reasoningEffortMappingCaption(
              model,
              reasoningEffort || 'medium',
              reasoningEfforts,
              reasoningMandatory,
            )}
          </p>
        )}
      </div>
      {Boolean(reasoningMandatory) && (
        <p className="muted small">This model always thinks — Off is not available.</p>
      )}
      {reasoningLocalSupport === 'none' && (
        <p className="muted small">
          This model has no thinking mode — its chat template never produces
          think-steps, so there is nothing to turn on.
        </p>
      )}
      {reasoningLocalSupport === 'toggle' && (
        <p className="muted small">
          This model thinks on or off only — it has no strength levels to pick.
        </p>
      )}
    </div>
  );
}
