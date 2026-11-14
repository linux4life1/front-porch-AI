// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice & Media → Expression Images, the desktop's
// VoiceMediaExpressionSection (voice_media_tab/expression_section.dart):
// the enable switch with "Enabled — <mode>, <display>", and while it is on
// Classification (with the ONNX model's ready check / download button),
// Display, Re-roll, Emoji Burst (+ its size while the burst is on) and
// Fallback, in the desktop's order and words.

import type { OnnxModel, VoiceMediaPatch, VoiceMediaStatus } from './useVoiceMediaWire';
import { VoiceMediaCard, VoiceMediaSubRow } from './VoiceMediaCard';
import {
  IconBackup,
  IconCelebration,
  IconCheck,
  IconDice,
  IconDownload,
  IconMood,
  IconPsychology,
  IconSidebar,
} from './voiceMediaIcons';

export const MODES: [string, string][] = [
  ['llm', 'LLM (Realism Engine)'],
  ['onnx', 'Local ONNX Model'],
  ['manual', 'Manual Only'],
];
export const DISPLAYS: [string, string][] = [
  ['sidebar', 'Sidebar Only'],
  ['background', 'Background Only'],
  ['both', 'Both'],
];
export const FALLBACKS: [string, string][] = [
  ['neutral', 'Neutral Sprite'],
  ['prime', 'Prime Avatar'],
  ['none', 'Hide'],
  ['emoji', 'Emoji Icon'],
];

/** `_expressionModeLabel` / `_expressionDisplayLabel`: the short words the
 *  subtitle uses (not the dropdown's longer ones). */
const MODE_SHORT: Record<string, string> = { llm: 'LLM', onnx: 'ONNX', manual: 'Manual' };
const DISPLAY_SHORT: Record<string, string> = {
  sidebar: 'Sidebar',
  background: 'Background',
  both: 'Both',
};

export function expressionSubtitle(s: VoiceMediaStatus): string {
  if (!s.expressionEnabled) return 'Disabled';
  const mode = s.expressionMode ?? '';
  const display = s.expressionDisplay ?? '';
  return `Enabled — ${MODE_SHORT[mode] ?? mode}, ${DISPLAY_SHORT[display] ?? display}`;
}

function Choice({
  label,
  value,
  options,
  onPick,
}: {
  label: string;
  value: string | undefined;
  options: [string, string][];
  onPick: (v: string) => void;
}) {
  return (
    <select
      className="setting-row-select vm-select"
      aria-label={label}
      value={value}
      onChange={(e) => onPick(e.target.value)}
    >
      {options.map(([v, text]) => (
        <option key={v} value={v}>
          {text}
        </option>
      ))}
    </select>
  );
}

/** `_OnnxDownloadButton`: a green check once the model is on disk, a
 *  spinner while it downloads, else the download button. */
function OnnxButton({ model, act }: { model: OnnxModel; act: (path: string, failure: string) => void }) {
  if (model.state === 'ready') {
    return (
      <span
        className="vm-onnx ready"
        role="img"
        aria-label="Expression model downloaded and ready"
        title="Expression model downloaded and ready"
      >
        <IconCheck size={18} />
      </span>
    );
  }
  const downloading = model.state === 'downloading';
  const pct = model.progress != null ? Math.round(model.progress * 100) : null;
  return (
    <button
      type="button"
      className={`vm-onnx${downloading ? ' busy' : ''}`}
      aria-label={
        downloading
          ? `Downloading the ONNX model${pct != null ? ` (${pct}%)` : ''}`
          : 'Download ONNX model for local expression classification'
      }
      title="Download ONNX model for local expression classification"
      disabled={downloading}
      onClick={() => act('/api/voice/onnx/download', 'Could not start the download:')}
    >
      {downloading ? <span className="vm-spinner" aria-hidden /> : <IconDownload size={20} />}
    </button>
  );
}

export function ExpressionImagesCard({
  status,
  write,
  act,
}: {
  status: VoiceMediaStatus;
  write: (p: VoiceMediaPatch) => void;
  act: (path: string, failure: string) => void;
}) {
  if (status.expressionEnabled === undefined) return null;
  const on = status.expressionEnabled;
  const size = Math.round(status.expressionEmojiBurstSize ?? 28);
  return (
    <VoiceMediaCard
      heading="Expression Images"
      icon={<IconMood />}
      iconTone={on ? 'accent' : 'off'}
      title="Expression Images"
      subtitle={expressionSubtitle(status)}
      testid="vm-expressions"
      control={
        <input
          type="checkbox"
          className="switch"
          aria-label="Expression Images"
          checked={on}
          onChange={(e) => write({ expressionEnabled: e.target.checked })}
        />
      }
    >
      {on && (
        <>
          <VoiceMediaSubRow icon={<IconPsychology size={16} />} label="Classification:" fill>
            <Choice
              label="Classification"
              value={status.expressionMode}
              options={MODES}
              onPick={(expressionMode) => write({ expressionMode })}
            />
            {status.onnxModel && <OnnxButton model={status.onnxModel} act={act} />}
          </VoiceMediaSubRow>
          {status.onnxModel?.failed && (
            <p className="vm-hint vm-error" role="alert">
              Download failed. Check your internet connection and try again.
            </p>
          )}
          <VoiceMediaSubRow icon={<IconSidebar size={16} />} label="Display:" fill>
            <Choice
              label="Display"
              value={status.expressionDisplay}
              options={DISPLAYS}
              onPick={(expressionDisplay) => write({ expressionDisplay })}
            />
          </VoiceMediaSubRow>
          <VoiceMediaSubRow icon={<IconDice size={16} />} label="Re-roll if same sprite repeats">
            <input
              type="checkbox"
              className="switch"
              aria-label="Re-roll if same sprite repeats"
              checked={!!status.expressionRerollSame}
              onChange={(e) => write({ expressionRerollSame: e.target.checked })}
            />
          </VoiceMediaSubRow>
          <VoiceMediaSubRow icon={<IconCelebration size={16} />} label="Expression Emoji Burst">
            <input
              type="checkbox"
              className="switch"
              aria-label="Expression Emoji Burst"
              checked={!!status.expressionEmojiBurst}
              onChange={(e) => write({ expressionEmojiBurst: e.target.checked })}
            />
          </VoiceMediaSubRow>
          {status.expressionEmojiBurst && (
            <div className="vm-slider">
              <div className="vm-slider-head">
                <span>Burst emoji size</span>
                <span>{size} px</span>
              </div>
              <input
                type="range"
                aria-label="Burst emoji size"
                min={12}
                max={60}
                step={4}
                value={size}
                onChange={(e) => write({ expressionEmojiBurstSize: Number(e.target.value) })}
              />
            </div>
          )}
          <VoiceMediaSubRow icon={<IconBackup size={16} />} label="Fallback:" fill>
            <Choice
              label="Fallback"
              value={status.expressionFallback}
              options={FALLBACKS}
              onPick={(expressionFallback) => write({ expressionFallback })}
            />
          </VoiceMediaSubRow>
        </>
      )}
    </VoiceMediaCard>
  );
}
