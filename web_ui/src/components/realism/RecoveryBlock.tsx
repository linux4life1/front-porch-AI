// "Recovery after intimacy": how a character comes down after climax. The
// card form shows it under the card's Afterglow switch, and Group Settings
// under each member's own (mirror of desktop RecoveryBlock).
import { Slider, SelectRow } from './controls';
import {
  PCD_OPTIONS,
  RECOVERY_MAX_MINUTES,
  RECOVERY_MIN_MINUTES,
  RECOVERY_PRESETS,
  recoveryClockOffHint,
  recoveryFromPreset,
  recoveryPresetKey,
  recoveryResolvesLine,
  recoverySoftGateHint,
  recoverySuggestionLine,
  recoveryWithMinutes,
  recoveryWithPcdMood,
  suggestRecoveryPresetKey,
  type RecoveryProfileValue,
} from './realismTypes';

/** Slider position when the card fixes no length: the middle named value,
 *  so the slider reads as "where Custom would start", not as a 0 that
 *  contradicts the judge-decides label. (Mirror of RecoveryBlock
 *  .neutralSliderMinutes on desktop.) */
const NEUTRAL_RECOVERY_MINUTES = 90;

export function RecoveryBlock({
  recovery,
  sex,
  intimateInto,
  intimateNotInto,
  onChange,
  showChargenSuggestion = false,
}: {
  recovery?: RecoveryProfileValue;
  sex?: string;
  intimateInto?: string[];
  intimateNotInto?: string[];
  onChange: (recovery: RecoveryProfileValue) => void;
  showChargenSuggestion?: boolean;
}) {
  const r = recovery ?? { recoveryMode: 'auto' as const, recoveryMinutes: null };
  const set = (patch: { recovery: RecoveryProfileValue }) => onChange(patch.recovery);
  const presetKey = recoveryPresetKey(r);
  // The soft gate has no length (decision 4) — its slider parked at a
  // misleading 90 and dragging it flipped the card to a hard lock.
  // Maintainer ruling 2026-10-18: hide it for 'none' (mirror of desktop
  // RecoveryBlock); a plain-English line takes its place.
  const softGate = presetKey === 'none';
  const sliderValue = r.recoveryMinutes ?? NEUTRAL_RECOVERY_MINUTES;
  const suggestion =
    showChargenSuggestion && presetKey === 'auto'
      ? recoverySuggestionLine(suggestRecoveryPresetKey(intimateInto ?? [], intimateNotInto ?? []))
      : null;
  return (
    <div className="recovery-block" data-testid="recovery-block">
      <span className="recovery-head">Recovery after intimacy</span>
      <p className="muted small">How this character comes down after climax.</p>
      <SelectRow
        label="Recovery preset"
        value={presetKey}
        options={RECOVERY_PRESETS.map((p) => ({ value: p.key, label: p.label }))}
        onChange={(key) =>
          set({
            recovery:
              key === 'custom'
                ? recoveryWithMinutes(r, sliderValue)
                : recoveryFromPreset(key, r.pcdMood ?? 'off'),
          })
        }
      />
      {!softGate && (
        <Slider
          label="Recovery minutes"
          min={RECOVERY_MIN_MINUTES}
          max={RECOVERY_MAX_MINUTES}
          value={sliderValue}
          badge={`${sliderValue} min`}
          onChange={(n) => set({ recovery: recoveryWithMinutes(r, n) })}
        />
      )}
      <small className="muted" data-testid="recovery-clock-off-hint">
        {softGate ? recoverySoftGateHint() : recoveryClockOffHint(r.recoveryMinutes)}
      </small>
      <small className="muted" data-testid="recovery-resolves-line">
        {recoveryResolvesLine(r, sex ?? '')}
      </small>
      {/* PR 8: the grey-drift dial. Opt-in by law — Off ships and Off is
          what every pre-PR-8 card reads (mirror of desktop RecoveryBlock). */}
      <div data-testid="recovery-pcd-row">
        <SelectRow
          label="Grey drift after"
          value={r.pcdMood ?? 'off'}
          options={PCD_OPTIONS.map((o) => ({ value: o.key, label: o.label }))}
          onChange={(mood) => set({ recovery: recoveryWithPcdMood(r, mood) })}
        />
        <small className="muted">
          A hollow, misty mood some people feel minutes to an hour after
          intimacy — real, brief, and not about their partner. How often it
          visits after a climax.
        </small>
      </div>
      {suggestion && (
        <small className="recovery-suggestion" data-testid="recovery-suggestion">
          {suggestion}
        </small>
      )}
    </div>
  );
}
