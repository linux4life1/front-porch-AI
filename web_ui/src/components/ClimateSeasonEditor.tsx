// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PWA twin of desktop season cards: rename, start day, add/remove 2–8.
// Overlap is a hard save block (same copy as desktop).

import { useMemo } from 'react';
import {
  allocSeasonId,
  applyRows,
  daysInMonth365,
  doyFromMonthDay,
  formatDoy,
  MAX_SEASONS,
  MIN_SEASONS,
  monthDayFromDoy,
  seasonPickerIso,
  rowsFromBiome,
  startInLongestGap,
  type BiomeDraft,
  type SeasonRow,
} from '../lib/seasonCalendar';

export function ClimateSeasonEditor({
  biome,
  onChange,
  errors,
  enabled = true,
}: {
  biome: BiomeDraft;
  onChange: (next: BiomeDraft) => void;
  errors: string[];
  /** WorldsPage hides this when the world's climateEnabled flag is off. */
  enabled?: boolean;
}) {
  if (!enabled) return null;
  const rows = useMemo(() => rowsFromBiome(biome), [biome]);
  const emit = (next: SeasonRow[]) => onChange(applyRows(biome, next));
  const clash = (id: string) => errors.some((e) => e.includes(id));

  return (
    <div className="climate-season-editor">
      <div className="muted small" style={{ marginBottom: 8 }}>
        2–8 seasons. Same start twice cannot save. Leave a name blank to keep
        winter / spring / summer / autumn.
      </div>
      <div className="climate-season-grid">
        {rows.map((row) => {
          const cap = daysInMonth365(row.month);
          const startLabel = formatDoy(doyFromMonthDay(row.month, row.day));
          const iso = seasonPickerIso(row.month, Math.min(row.day, cap));
          return (
          <div
            key={row.id}
            className={`climate-season-card${clash(row.id) ? ' clash' : ''}`}
          >
            <div className="climate-season-card-head">
              <input
                value={row.label}
                placeholder={
                  ['winter', 'spring', 'summer', 'autumn'].includes(row.id)
                    ? row.id[0].toUpperCase() + row.id.slice(1)
                    : 'New season'
                }
                onChange={(e) =>
                  emit(
                    rows.map((r) =>
                      r.id === row.id ? { ...r, label: e.target.value } : r,
                    ),
                  )
                }
              />
              {rows.length > MIN_SEASONS && (
                <button
                  type="button"
                  className="ghost"
                  title="Remove season"
                  onClick={() => emit(rows.filter((r) => r.id !== row.id))}
                >
                  ×
                </button>
              )}
            </div>
            <div className="climate-season-dates">
              <span className="climate-season-date">{startLabel}</span>
              <input
                type="date"
                min="1900-01-01"
                max="2100-12-31"
                aria-label={`Season starts ${startLabel}`}
                value={iso}
                onChange={(e) => {
                  if (!e.target.value) return;
                  const parts = e.target.value.split('-');
                  const month = Number(parts[1]);
                  const d = Number(parts[2]);
                  emit(
                    rows.map((r) =>
                      r.id === row.id
                        ? {
                            ...r,
                            month,
                            day: Math.min(d, daysInMonth365(month)),
                          }
                        : r,
                    ),
                  );
                }}
              />
            </div>
          </div>
          );
        })}
        {rows.length < MAX_SEASONS && (
          <button
            type="button"
            className="climate-season-add"
            onClick={() => {
              const id = allocSeasonId(rows.map((r) => r.id));
              const current = Object.fromEntries(
                rows.map((r) => [r.id, doyFromMonthDay(r.month, r.day)]),
              );
              const md = monthDayFromDoy(startInLongestGap(current));
              emit([
                ...rows,
                {
                  id,
                  label: `Season ${rows.length + 1}`,
                  month: md.month,
                  day: md.day,
                },
              ]);
            }}
          >
            + Season
          </button>
        )}
      </div>
      {errors.length > 0 && (
        <ul className="climate-season-errors">
          {errors.map((e) => (
            <li key={e}>⛔ {e}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
