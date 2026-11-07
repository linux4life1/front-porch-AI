// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Generation preset" for one model, beside the model on the Models page's
// Local model card, Settings' Chat speech card and the chat's model sheet
// (the desktop's picker next to the .kcpps one). A preset picked here loads
// whenever that model becomes the chat model, and at once when it already
// is. "None" keeps whatever values are set when the model is picked.

import type { GenPresets } from './genPresets';
import { useGenPresets } from './useGenPresets';

type Act = (action: string, body?: Record<string, unknown>) => Promise<GenPresets | null>;

export function ModelPresetSelect({
  data,
  act,
  modelKey,
  label = 'Generation preset for this model',
  onLinked,
}: {
  data: GenPresets | null;
  act: Act;
  /** The host's ChatModelId key; nothing shows without one. */
  modelKey: string | null;
  label?: string;
  /** Called when the link loaded the preset now (the chat model's). */
  onLinked?: (next: GenPresets) => void;
}) {
  if (!data || !modelKey) return null;
  const linked = data.links[modelKey];
  const value = linked && data.presets.some((p) => p.name === linked) ? linked : '';
  const current = data.model?.key === modelKey;
  return (
    <label className="gp-model" data-testid="model-gen-preset">
      {label}
      <select
        value={value}
        onChange={async (e) => {
          const next = await act('link', { name: e.target.value || null, modelKey });
          if (next && current) onLinked?.(next);
        }}
      >
        <option value="">None (keep current values)</option>
        {data.presets.map((p) => (
          <option key={p.name} value={p.name}>{p.name}</option>
        ))}
      </select>
      <span className="muted small">
        {data.presets.length === 0
          ? 'Save a preset in Settings → Generation to pick it here.'
          : current
            ? 'Loads now and every time this model is picked.'
            : 'Loads every time this model is picked.'}
      </span>
    </label>
  );
}

/** [ModelPresetSelect] with its own read of the presets (once: the cards
 *  it sits on poll or close soon, and a link is this picker's own write). */
export function LiveModelPresetSelect(props: {
  modelKey: string | null;
  label?: string;
}) {
  const { data, error, act } = useGenPresets(false);
  return (
    <>
      <ModelPresetSelect data={data} act={act} {...props} />
      {error && <p className="error" role="alert">{error}</p>}
    </>
  );
}
