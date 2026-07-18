// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared lorebook entry editor used by the create wizard and the character edit
// page so both author lore identically. Each entry: name, trigger keywords
// (comma-separated), content, an "enabled" flag, an "always active" (constant)
// flag, and a sticky-depth (how many turns an activated entry lingers). A JSON
// import button bulk-loads SillyTavern / Chub / Front Porch lorebooks.

import { useRef, useState } from 'react';
import { MacroField } from './MacroField';

export interface LoreEntry {
  name: string;
  key: string;
  content: string;
  enabled: boolean;
  constant: boolean;
  stickyDepth: number;
  /** Chance to trigger, 0-100 (Simple-level ST field). */
  probability?: number;
  /** ST position 0-6 (Simple-level placement preset). */
  position?: number;
  // ── Advanced tier (present-key-only overrides; absent = keep ext value) ──
  secondaryKeys?: string;
  selectiveLogic?: number;
  useRegex?: boolean;
  order?: number;
  depth?: number;
  role?: number;
  sticky?: number;
  cooldown?: number;
  delay?: number;
  scanDepth?: number | null;
  caseSensitive?: boolean | null;
  matchWholeWords?: boolean | null;
  excludeRecursion?: boolean;
  preventRecursion?: boolean;
  delayUntilRecursion?: number;
  group?: string;
  groupWeight?: number;
  groupOverride?: boolean;
  useGroupScoring?: boolean | null;
  ignoreBudget?: boolean;
  /** Opaque full-fidelity entry blob from the server (advanced/imported ST
   *  fields). Never edited here — round-tripped untouched so saving from the
   *  web can't strip metadata the desktop model carries. */
  ext?: unknown;
}

export const LORE_LOGIC: Record<number, string> = {
  0: 'AND any of them',
  1: 'NOT all of them',
  2: 'NOT any of them',
  3: 'AND all of them',
};

/** Tri-state (Use global / On / Off) select for nullable boolean overrides. */
function TriSelect({
  value,
  onChange,
}: {
  value: boolean | null | undefined;
  onChange: (v: boolean | null) => void;
}) {
  return (
    <select
      value={value == null ? 'global' : value ? 'on' : 'off'}
      onChange={(e) =>
        onChange(e.target.value === 'global' ? null : e.target.value === 'on')
      }
    >
      <option value="global">Use global</option>
      <option value="on">On</option>
      <option value="off">Off</option>
    </select>
  );
}

export const LORE_POSITIONS: Record<number, string> = {
  0: 'With character info',
  1: 'After character info',
  2: "Author's Note — top",
  3: "Author's Note — bottom",
  4: 'In recent chat (@depth)',
  5: 'Examples — top',
  6: 'Examples — bottom',
};

export function LoreEntriesEditor({
  entries,
  onChange,
}: {
  entries: LoreEntry[];
  onChange: (entries: LoreEntry[]) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [advancedOpen, setAdvancedOpen] = useState<Record<number, boolean>>({});

  const add = () =>
    onChange([...entries, { name: '', key: '', content: '', enabled: true, constant: false, stickyDepth: 1 }]);
  const remove = (i: number) => onChange(entries.filter((_, j) => j !== i));
  const update = (i: number, patch: Partial<LoreEntry>) => {
    const next = [...entries];
    next[i] = { ...next[i], ...patch };
    onChange(next);
  };

  const importFile = async (file: File) => {
    try {
      const parsed = parseLorebookJson(await file.text());
      if (parsed.length) onChange([...entries, ...parsed]);
    } catch {
      // Ignore malformed files — the picker simply does nothing.
    }
  };

  return (
    <>
      <div className="row-label">
        <span>Lorebook entries</span>
        <div className="row-actions">
          <button className="ghost" onClick={() => fileRef.current?.click()}>
            Import JSON
          </button>
          <button className="ghost" onClick={add}>
            + Add entry
          </button>
        </div>
      </div>
      <input
        ref={fileRef}
        type="file"
        accept=".json,application/json"
        style={{ display: 'none' }}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) importFile(f);
          e.target.value = '';
        }}
      />
      {entries.length === 0 && (
        <p className="muted">No entries. Lore is injected when its keywords appear in the chat.</p>
      )}
      {entries.map((entry, i) => (
        <div className="card lore-edit" key={i}>
          <input
            placeholder="Entry name"
            value={entry.name}
            onChange={(e) => update(i, { name: e.target.value })}
          />
          <input
            placeholder="Trigger keywords (comma-separated)"
            value={entry.key}
            onChange={(e) => update(i, { key: e.target.value })}
          />
          <MacroField
            placeholder="Lore content"
            rows={3}
            value={entry.content}
            onChange={(val) => update(i, { content: val })}
          />
          <div className="lore-edit-controls">
            <label className="tool-toggle">
              <span>Enabled</span>
              <input
                type="checkbox"
                checked={entry.enabled}
                onChange={(e) => update(i, { enabled: e.target.checked })}
              />
            </label>
            <label className="tool-toggle">
              <span>Always active</span>
              <input
                type="checkbox"
                checked={entry.constant}
                onChange={(e) => update(i, { constant: e.target.checked })}
              />
            </label>
            <label className="tool-num">
              <span>Sticky depth</span>
              <input
                type="number"
                min={1}
                value={entry.stickyDepth}
                onChange={(e) => update(i, { stickyDepth: Math.max(1, parseInt(e.target.value, 10) || 1) })}
              />
            </label>
            <label className="tool-num">
              <span>Chance %</span>
              <input
                type="number"
                min={0}
                max={100}
                value={entry.probability ?? 100}
                onChange={(e) =>
                  update(i, {
                    probability: Math.min(100, Math.max(0, parseInt(e.target.value, 10) || 0)),
                  })
                }
              />
            </label>
            <label className="tool-num">
              <span>Placement</span>
              <select
                value={entry.position ?? 0}
                onChange={(e) => update(i, { position: parseInt(e.target.value, 10) })}
              >
                {Object.entries(LORE_POSITIONS).map(([v, label]) => (
                  <option key={v} value={v}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <button className="ghost" onClick={() => remove(i)}>
              Remove
            </button>
            <button
              className="ghost"
              onClick={() => setAdvancedOpen((o) => ({ ...o, [i]: !o[i] }))}
            >
              {advancedOpen[i] ? 'Advanced ▾' : 'Advanced ▸'}
            </button>
          </div>
          {advancedOpen[i] && (
            <div className="lore-advanced">
              <label className="lore-adv-wide">
                <span>Secondary keywords (comma separated)</span>
                <input
                  value={entry.secondaryKeys ?? ''}
                  onChange={(e) => update(i, { secondaryKeys: e.target.value })}
                />
              </label>
              <label>
                <span>Secondary logic</span>
                <select
                  value={entry.selectiveLogic ?? 0}
                  onChange={(e) => update(i, { selectiveLogic: parseInt(e.target.value, 10) })}
                >
                  {Object.entries(LORE_LOGIC).map(([v, label]) => (
                    <option key={v} value={v}>{label}</option>
                  ))}
                </select>
              </label>
              <label className="tool-toggle">
                <span>Keywords are regex</span>
                <input
                  type="checkbox"
                  checked={entry.useRegex ?? false}
                  onChange={(e) => update(i, { useRegex: e.target.checked })}
                />
              </label>
              <label>
                <span>Order</span>
                <input
                  type="number"
                  value={entry.order ?? 100}
                  onChange={(e) => update(i, { order: parseInt(e.target.value, 10) || 100 })}
                />
              </label>
              {(entry.position ?? 0) === 4 && (
                <>
                  <label>
                    <span>Depth</span>
                    <input
                      type="number"
                      min={0}
                      value={entry.depth ?? 4}
                      onChange={(e) => update(i, { depth: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                    />
                  </label>
                  <label>
                    <span>Speak as</span>
                    <select
                      value={entry.role ?? 0}
                      onChange={(e) => update(i, { role: parseInt(e.target.value, 10) })}
                    >
                      <option value={0}>System</option>
                      <option value={1}>User</option>
                      <option value={2}>Assistant</option>
                    </select>
                  </label>
                </>
              )}
              <label>
                <span>Sticky (msgs)</span>
                <input
                  type="number"
                  min={0}
                  value={entry.sticky ?? 0}
                  onChange={(e) => update(i, { sticky: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <label>
                <span>Cooldown</span>
                <input
                  type="number"
                  min={0}
                  value={entry.cooldown ?? 0}
                  onChange={(e) => update(i, { cooldown: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <label>
                <span>Delay</span>
                <input
                  type="number"
                  min={0}
                  value={entry.delay ?? 0}
                  onChange={(e) => update(i, { delay: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <label>
                <span>Scan depth (empty = global)</span>
                <input
                  type="number"
                  min={0}
                  value={entry.scanDepth ?? ''}
                  onChange={(e) =>
                    update(i, {
                      scanDepth: e.target.value === '' ? null : Math.max(0, parseInt(e.target.value, 10) || 0),
                    })
                  }
                />
              </label>
              <label>
                <span>Case sensitive</span>
                <TriSelect
                  value={entry.caseSensitive}
                  onChange={(v) => update(i, { caseSensitive: v })}
                />
              </label>
              <label>
                <span>Whole words</span>
                <TriSelect
                  value={entry.matchWholeWords}
                  onChange={(v) => update(i, { matchWholeWords: v })}
                />
              </label>
              <label className="tool-toggle">
                <span>Can be chained by lore</span>
                <input
                  type="checkbox"
                  checked={!(entry.excludeRecursion ?? false)}
                  onChange={(e) => update(i, { excludeRecursion: !e.target.checked })}
                />
              </label>
              <label className="tool-toggle">
                <span>Can chain other lore</span>
                <input
                  type="checkbox"
                  checked={!(entry.preventRecursion ?? false)}
                  onChange={(e) => update(i, { preventRecursion: !e.target.checked })}
                />
              </label>
              <label>
                <span>Only via chaining, level</span>
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={entry.delayUntilRecursion ?? 0}
                  onChange={(e) => update(i, { delayUntilRecursion: Math.max(0, Math.min(10, parseInt(e.target.value, 10) || 0)) })}
                />
              </label>
              <label>
                <span>Variety group</span>
                <input
                  value={entry.group ?? ''}
                  onChange={(e) => update(i, { group: e.target.value })}
                />
              </label>
              <label>
                <span>Group weight</span>
                <input
                  type="number"
                  min={1}
                  value={entry.groupWeight ?? 100}
                  onChange={(e) => update(i, { groupWeight: Math.max(1, parseInt(e.target.value, 10) || 100) })}
                />
              </label>
              <label className="tool-toggle">
                <span>Prioritize in group</span>
                <input
                  type="checkbox"
                  checked={entry.groupOverride ?? false}
                  onChange={(e) => update(i, { groupOverride: e.target.checked })}
                />
              </label>
              <label>
                <span>Score by matched keys</span>
                <TriSelect
                  value={entry.useGroupScoring}
                  onChange={(v) => update(i, { useGroupScoring: v })}
                />
              </label>
              <label className="tool-toggle">
                <span>Ignore token budget</span>
                <input
                  type="checkbox"
                  checked={entry.ignoreBudget ?? false}
                  onChange={(e) => update(i, { ignoreBudget: e.target.checked })}
                />
              </label>
            </div>
          )}
        </div>
      ))}
    </>
  );
}

/** Tolerant parser covering Front Porch / Chub (entries: array) and
 *  SillyTavern (entries: keyed object) lorebook exports. Unknown shapes yield
 *  an empty list rather than throwing into the UI. */
function parseLorebookJson(text: string): LoreEntry[] {
  const data = JSON.parse(text);
  const rawEntries = Array.isArray(data)
    ? data
    : Array.isArray(data?.entries)
      ? data.entries
      : data?.entries && typeof data.entries === 'object'
        ? Object.values(data.entries)
        : [];
  const out: LoreEntry[] = [];
  for (const e of rawEntries as Record<string, unknown>[]) {
    if (!e || typeof e !== 'object') continue;
    const keys = e.keys ?? e.key ?? e.keywords;
    const keyStr = Array.isArray(keys) ? keys.join(', ') : String(keys ?? '');
    const content = String(e.content ?? e.entry ?? '');
    if (!keyStr.trim() && !content.trim()) continue;
    out.push({
      name: String(e.comment ?? e.name ?? ''),
      key: keyStr,
      content,
      enabled: e.enabled !== false && e.disable !== true,
      constant: e.constant === true,
      probability:
        typeof e.probability === 'number'
          ? Math.min(100, Math.max(0, e.probability))
          : undefined,
      position:
        typeof e.position === 'number' && e.position >= 0 && e.position <= 6
          ? e.position
          : undefined,
      // Carry the raw source entry so the server-side tolerant decoder keeps
      // every ST/Chub field (secondary keys, probability, position, …).
      ext: e,
      // Clamp to >=1: the Dart Lorebook model coerces 0 -> 1 on PNG reload, so a
      // stored 0 would silently change after a round-trip. Keep it stable here.
      stickyDepth: Math.max(
        1,
        typeof e.sticky_depth === 'number'
          ? e.sticky_depth
          : typeof e.stickyDepth === 'number'
            ? e.stickyDepth
            : 1,
      ),
    });
  }
  return out;
}
