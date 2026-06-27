// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared lorebook entry editor used by the create wizard and the character edit
// page so both author lore identically. Each entry: name, trigger keywords
// (comma-separated), content, an "enabled" flag, an "always active" (constant)
// flag, and a sticky-depth (how many turns an activated entry lingers). A JSON
// import button bulk-loads SillyTavern / Chub / Front Porch lorebooks.

import { useRef } from 'react';
import { MacroField } from './MacroField';

export interface LoreEntry {
  name: string;
  key: string;
  content: string;
  enabled: boolean;
  constant: boolean;
  stickyDepth: number;
}

export function LoreEntriesEditor({
  entries,
  onChange,
}: {
  entries: LoreEntry[];
  onChange: (entries: LoreEntry[]) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);

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
            <button className="ghost" onClick={() => remove(i)}>
              Remove
            </button>
          </div>
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
