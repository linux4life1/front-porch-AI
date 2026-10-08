// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { loraBadge } from './deskRules';
import type { LoraFact, LoraSlot, ReadyFacts } from './types';

/** The LoRAs on the desk, their weights and whether they fit the model. */
export function DeskLoras(props: {
  slots: LoraSlot[];
  facts: ReadyFacts | null;
  known: Record<string, LoraFact>;
  onWeights: (next: LoraSlot[]) => void;
  onAdd: () => void;
  onCivitai: () => void;
  onUseAnyway: (family: string) => void;
}) {
  const filled = props.slots.filter((slot) => slot.file.trim());
  const family = props.facts?.loraFamily;
  const blocked = props.facts?.kind === 'loraMismatch';
  return (
    <div className="fp-lora-controls">
      <div>LoRA</div>
      {filled.map((slot) => (
        <div key={slot.file}>
          <span>{slot.file}</span>
          <span>{loraBadge(slot.file, family, props.known)}</span>
          <label>
            Weight
            <input
              aria-label={`Weight ${slot.file}`}
              type="number"
              min={0}
              max={1}
              step={0.05}
              defaultValue={String(slot.weight)}
              onBlur={(e) => {
                const weight = Number(e.target.value);
                props.onWeights(
                  props.slots.map((row) => (row.file === slot.file ? { ...row, weight } : row)),
                );
              }}
            />
          </label>
          <button
            type="button"
            onClick={() =>
              props.onWeights(props.slots.map((row) => (row.file === slot.file ? { ...row, file: '' } : row)))
            }
          >
            {`Remove ${slot.file}`}
          </button>
        </div>
      ))}
      {blocked && family ? (
        <p>
          Generate stays off until you pick a matching LoRA or press Use anyway.
          <button type="button" onClick={() => props.onUseAnyway(family)}>
            Use anyway
          </button>
        </p>
      ) : null}
      <button type="button" onClick={props.onAdd}>
        Add
      </button>
      <button type="button" onClick={props.onCivitai}>
        Get a LoRA from CivitAI
      </button>
    </div>
  );
}
