// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Compact opening-state editor for one alternate greeting. Off (null) =
// reading-the-room; on = authored seed (blank fields inherit card defaults).
// Toggle-on with no fields persists null, not {}. Toggle off/on restores the
// last authored seed (including a desktop calendar) instead of wiping to {}.

import { useEffect, useRef, useState } from 'react';
import { Slider, SelectRow, ToggleRow } from './realism/controls';
import { ChipList } from './realism/ChipList';
import {
  type GreetingSeed,
  INTENSITY_OPTIONS,
  TIME_OPTIONS,
  chipsToInventory,
  inventoryToChips,
  titleCase,
} from './realism/realismTypes';

export function GreetingSeedForm({
  seed,
  onChange,
  showNeeds = false,
  showInventory = false,
}: {
  seed: GreetingSeed | null;
  onChange: (next: GreetingSeed | null) => void;
  showNeeds?: boolean;
  showInventory?: boolean;
}) {
  const stash = useRef<GreetingSeed | null>(seed);
  const [uiOn, setUiOn] = useState(seed != null);
  useEffect(() => {
    if (seed != null) {
      stash.current = seed;
      setUiOn(true);
    }
  }, [seed]);

  const enabled = uiOn || seed != null;
  const s = seed ?? {};
  const patch = (p: Partial<GreetingSeed>) => onChange({ ...s, ...p });
  const wardrobe = inventoryToChips(s.inventory ?? {});
  return (
    <div className="greeting-seed">
      <ToggleRow
        label="Custom opening state"
        hint={
          enabled
            ? 'Blank fields inherit the card. This alt will not read the room once a seed is authored.'
            : 'No seed — the engine reads the room from this greeting.'
        }
        value={enabled}
        onChange={(on) => {
          if (on) {
            setUiOn(true);
            // Restore last authored seed (calendar / {}). Fresh enable stays
            // null — not {} — until a field is set.
            onChange(stash.current);
          } else {
            stash.current = seed;
            setUiOn(false);
            onChange(null);
          }
        }}
      />
      {enabled && (
        <>
          <label>
            Emotion
            <input
              value={s.characterEmotion ?? ''}
              placeholder="e.g. furious, warm, guarded"
              onChange={(e) =>
                patch({ characterEmotion: e.target.value.trim() || undefined })
              }
            />
          </label>
          <SelectRow
            label="Intensity"
            value={s.emotionIntensity ?? ''}
            placeholder="inherit (mild)"
            options={INTENSITY_OPTIONS.map((i) => ({ value: i, label: titleCase(i) }))}
            onChange={(v) => patch({ emotionIntensity: v || undefined })}
          />
          <Slider
            label="Short-term bond"
            min={-300}
            max={300}
            value={s.shortTermBond ?? 0}
            unset={s.shortTermBond === undefined}
            onChange={(n) => patch({ shortTermBond: n })}
            onClear={() => patch({ shortTermBond: undefined })}
          />
          <Slider
            label="Long-term bond"
            min={-300}
            max={300}
            value={s.longTermBond ?? 0}
            unset={s.longTermBond === undefined}
            onChange={(n) => patch({ longTermBond: n })}
            onClear={() => patch({ longTermBond: undefined })}
          />
          <Slider
            label="Trust"
            min={-100}
            max={100}
            value={s.trustLevel ?? 0}
            unset={s.trustLevel === undefined}
            onChange={(n) => patch({ trustLevel: n })}
            onClear={() => patch({ trustLevel: undefined })}
          />
          <SelectRow
            label="Time of day"
            value={s.timeOfDay ?? ''}
            placeholder="inherit (morning)"
            options={TIME_OPTIONS.map((t) => ({ value: t, label: titleCase(t) }))}
            onChange={(v) => patch({ timeOfDay: v || undefined })}
          />
          <label>
            Day number
            <input
              type="number"
              min={1}
              value={s.dayCount ?? ''}
              placeholder="inherit (day 1)"
              onChange={(e) => {
                const n = parseInt(e.target.value, 10);
                patch({ dayCount: Number.isFinite(n) && n >= 1 ? n : undefined });
              }}
            />
          </label>
          <label>
            Story begins
            <input
              type="date"
              value={s.storyStartDate ?? ''}
              onChange={(e) =>
                patch({ storyStartDate: e.target.value || undefined })
              }
            />
          </label>
          <label>
            Opens at
            <input
              type="time"
              value={s.storyStartTime ?? ''}
              onChange={(e) =>
                patch({ storyStartTime: e.target.value || undefined })
              }
            />
          </label>
          <label>
            Starting task
            <input
              value={s.currentTask ?? ''}
              placeholder="Optional in-voice objective"
              onChange={(e) =>
                patch({ currentTask: e.target.value.trim() || undefined })
              }
            />
          </label>
          {showNeeds && (
            <>
              <p className="muted small">Needs baselines (0–100). Blank inherits the card.</p>
              {NEEDS.map(([key, label]) => (
                <Slider
                  key={key}
                  label={label}
                  min={0}
                  max={100}
                  value={(s[key] as number | undefined) ?? 80}
                  unset={(s[key] as number | undefined) === undefined}
                  onChange={(n) => patch({ [key]: n })}
                  onClear={() => patch({ [key]: undefined })}
                />
              ))}
            </>
          )}
          {showInventory && (
            <>
              <ChipList
                label="Wearing (this opening)"
                values={wardrobe.worn}
                onChange={(worn) =>
                  patch({ inventory: chipsToInventory(worn, wardrobe.carrying) })
                }
              />
              <ChipList
                label="Carrying (this opening)"
                values={wardrobe.carrying}
                onChange={(carrying) =>
                  patch({ inventory: chipsToInventory(wardrobe.worn, carrying) })
                }
              />
            </>
          )}
        </>
      )}
    </div>
  );
}

const NEEDS: [keyof GreetingSeed & string, string][] = [
  ['needsBaselineHunger', 'Hunger'],
  ['needsBaselineBladder', 'Bladder'],
  ['needsBaselineEnergy', 'Energy'],
  ['needsBaselineSocial', 'Social'],
  ['needsBaselineFun', 'Fun'],
  ['needsBaselineHygiene', 'Hygiene'],
  ['needsBaselineComfort', 'Comfort'],
];
