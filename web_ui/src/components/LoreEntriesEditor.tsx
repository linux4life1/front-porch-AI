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
  5: 'Example dialogues — top',
  6: 'Example dialogues — bottom',
};

/** One lore entry's fields: the Simple tab or the Advanced grid, the same
 *  rows as the desktop entry dialog. */
export function LoreEntryFields({
  entry,
  update,
  tab,
}: {
  entry: LoreEntry;
  update: (patch: Partial<LoreEntry>) => void;
  tab: 'simple' | 'advanced';
}) {
  return tab === 'simple' ? (
    <>
          <input
            placeholder="Name (optional)"
            value={entry.name}
            onChange={(e) => update({ name: e.target.value })}
          />
          <input
            placeholder={entry.constant ? 'Keywords (Disabled — Always Active)' : 'Keywords (comma separated)'}
            disabled={entry.constant}
            value={entry.key}
            onChange={(e) => update({ key: e.target.value })}
          />
          <MacroField
            placeholder="Enter lore content..."
            rows={3}
            value={entry.content}
            onChange={(val) => update({ content: val })}
          />
          <div className="lore-edit-controls">
            <label className="tool-toggle">
              <span>Enabled</span>
                <small className="muted">This entry can be injected when its keys match</small>
              <input
                type="checkbox"
                checked={entry.enabled}
                onChange={(e) => update({ enabled: e.target.checked })}
              />
            </label>
            <label className="tool-toggle">
              <span>Always Active</span>
                <small className="muted">Always considered active (ignores trigger keys)</small>
              <input
                type="checkbox"
                checked={entry.constant}
                onChange={(e) => update({ constant: e.target.checked })}
              />
            </label>
            {!entry.constant && (
              <>
                <label className="tool-num">
                  <span>Sticky Depth</span>
                  <small className="muted">How many turns the entry stays active after triggering</small>
                  <input
                    type="range"
                    min={1}
                    max={50}
                    value={Math.min(50, Math.max(1, entry.stickyDepth))}
                    onChange={(e) => update({ stickyDepth: parseInt(e.target.value, 10) })}
                  />
                  <output>{entry.stickyDepth}</output>
                </label>
                <label className="tool-num">
                  <span>Chance to trigger</span>
                  <small className="muted">Rolled each time the keywords match</small>
                  <input
                    type="range"
                    min={0}
                    max={100}
                    value={entry.probability ?? 100}
                    onChange={(e) => update({ probability: parseInt(e.target.value, 10) })}
                  />
                  <output>{entry.probability ?? 100}%</output>
                </label>
              </>
            )}
            <label className="tool-num">
              <span>Placement</span>
                <small className="muted">Where this entry lands in the prompt</small>
              <select
                value={entry.position ?? 0}
                onChange={(e) => update({ position: parseInt(e.target.value, 10) })}
              >
                {Object.entries(LORE_POSITIONS).map(([v, label]) => (
                  <option key={v} value={v}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          </div>
    </>
  ) : (
            <div className="lore-advanced">
              <h4 className="lore-adv-head lore-adv-wide">Conditions</h4>
              <label className="lore-adv-wide">
                <span>Secondary keywords (comma separated)</span>
                <input
                  value={entry.secondaryKeys ?? ''}
                  onChange={(e) => update({ secondaryKeys: e.target.value })}
                />
              </label>
              <label>
                <span>Secondary logic</span>
                <small className="muted">How secondary keywords gate the trigger</small>
                <select
                  value={entry.selectiveLogic ?? 0}
                  onChange={(e) => update({ selectiveLogic: parseInt(e.target.value, 10) })}
                >
                  {Object.entries(LORE_LOGIC).map(([v, label]) => (
                    <option key={v} value={v}>{label}</option>
                  ))}
                </select>
              </label>
              <label className="tool-toggle">
                <span>Keywords are regex patterns</span>
                <small className="muted">Treat every keyword as a regular expression</small>
                <input
                  type="checkbox"
                  checked={entry.useRegex ?? false}
                  onChange={(e) => update({ useRegex: e.target.checked })}
                />
              </label>
              <h4 className="lore-adv-head lore-adv-wide">Placement &amp; priority</h4>
              <label>
                <span>Position</span>
                <select
                  value={entry.position ?? 0}
                  onChange={(e) => update({ position: parseInt(e.target.value, 10) })}
                >
                  {Object.entries(LORE_POSITIONS).map(([v, label]) => (
                    <option key={v} value={v}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              {(entry.position ?? 0) === 4 && (
                <>
                <label>
                  <span>Depth</span>
                <small className="muted">Messages up from the end of the chat</small>
                  <input
                    type="number"
                    min={0}
                    value={entry.depth ?? 4}
                    onChange={(e) => update({ depth: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                  />
                </label>
                <label>
                  <span>Speak as</span>
                  <select
                    value={entry.role ?? 0}
                    onChange={(e) => update({ role: parseInt(e.target.value, 10) })}
                  >
                    <option value={0}>System</option>
                    <option value={1}>User</option>
                    <option value={2}>Assistant</option>
                  </select>
                </label>
                </>
              )}
              <label>
                <span>Order</span>
                <small className="muted">Higher = closer to the reply, survives budget cuts</small>
                <input
                  type="number"
                  value={entry.order ?? 100}
                  onChange={(e) => update({ order: parseInt(e.target.value, 10) || 100 })}
                />
              </label>
              <label className="tool-toggle">
                <span>Ignore token budget</span>
                <small className="muted">Always inject, even when lore is over budget</small>
                <input
                  type="checkbox"
                  checked={entry.ignoreBudget ?? false}
                  onChange={(e) => update({ ignoreBudget: e.target.checked })}
                />
              </label>
              <h4 className="lore-adv-head lore-adv-wide">Timing (messages)</h4>
              <label>
                <span>Sticky</span>
                <small className="muted">Stays force-active this many messages</small>
                <input
                  type="number"
                  min={0}
                  value={entry.sticky ?? 0}
                  onChange={(e) => update({ sticky: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <label>
                <span>Cooldown</span>
                <small className="muted">Cannot re-trigger for this many messages</small>
                <input
                  type="number"
                  min={0}
                  value={entry.cooldown ?? 0}
                  onChange={(e) => update({ cooldown: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <label>
                <span>Delay</span>
                <small className="muted">Silent until the chat reaches this length</small>
                <input
                  type="number"
                  min={0}
                  value={entry.delay ?? 0}
                  onChange={(e) => update({ delay: Math.max(0, parseInt(e.target.value, 10) || 0) })}
                />
              </label>
              <h4 className="lore-adv-head lore-adv-wide">Chain reactions</h4>
              <label className="tool-toggle">
                <span>Can be triggered by other lore</span>
                <input
                  type="checkbox"
                  checked={!(entry.excludeRecursion ?? false)}
                  onChange={(e) => update({ excludeRecursion: !e.target.checked })}
                />
              </label>
              <label className="tool-toggle">
                <span>Can trigger other lore</span>
                <input
                  type="checkbox"
                  checked={!(entry.preventRecursion ?? false)}
                  onChange={(e) => update({ preventRecursion: !e.target.checked })}
                />
              </label>
              <label>
                <span>Only via chaining, level</span>
                <small className="muted">0 = off; N = activates on chain sweep N+</small>
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={entry.delayUntilRecursion ?? 0}
                  onChange={(e) => update({ delayUntilRecursion: Math.max(0, Math.min(10, parseInt(e.target.value, 10) || 0)) })}
                />
              </label>
              <h4 className="lore-adv-head lore-adv-wide">Matching overrides</h4>
              <label>
                <span>Scan depth</span>
                <small className="muted">Messages this entry watches (empty = global)</small>
                <input
                  type="number"
                  min={0}
                  value={entry.scanDepth ?? ''}
                  onChange={(e) =>
                    update({
                      scanDepth: e.target.value === '' ? null : Math.max(0, parseInt(e.target.value, 10) || 0),
                    })
                  }
                />
              </label>
              <label>
                <span>Case sensitive</span>
                <TriSelect
                  value={entry.caseSensitive}
                  onChange={(v) => update({ caseSensitive: v })}
                />
              </label>
              <label>
                <span>Whole words</span>
                <TriSelect
                  value={entry.matchWholeWords}
                  onChange={(v) => update({ matchWholeWords: v })}
                />
              </label>
              <label>
                <span>Variety group</span>
                <input
                  value={entry.group ?? ''}
                  onChange={(e) => update({ group: e.target.value })}
                />
              </label>
              <label>
                <span>Weight</span>
                <small className="muted">Random-pick weight within the group</small>
                <input
                  type="number"
                  min={1}
                  value={entry.groupWeight ?? 100}
                  onChange={(e) => update({ groupWeight: Math.max(1, parseInt(e.target.value, 10) || 100) })}
                />
              </label>
              <label className="tool-toggle">
                <span>Prioritize in group</span>
                <small className="muted">Wins the group by Order instead of randomly</small>
                <input
                  type="checkbox"
                  checked={entry.groupOverride ?? false}
                  onChange={(e) => update({ groupOverride: e.target.checked })}
                />
              </label>
              <label>
                <span>Score by matched keys</span>
                <TriSelect
                  value={entry.useGroupScoring}
                  onChange={(v) => update({ useGroupScoring: v })}
                />
              </label>
            </div>
  );
}

function blankEntry(): LoreEntry {
  return { name: '', key: '', content: '', enabled: true, constant: false, stickyDepth: 1 };
}

export function LoreEntriesEditor({
  entries,
  onChange,
  title = 'Lorebook entries',
  emptyText = 'No entries. Lore is injected when its keywords appear in the chat.',
  note,
  editorChrome,
}: {
  entries: LoreEntry[];
  onChange: (entries: LoreEntry[]) => void;
  title?: string;
  emptyText?: string;
  /** One line under the header, e.g. lore a place inherits. */
  note?: string | null;
  /** The character editor's header: the desktop editor's four actions in its
   *  order, its empty state, and no title (the page prints "Lorebook"). */
  editorChrome?: { onFromCharacter: () => void; fileName: string };
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [editing, setEditing] = useState<{ index: number | null; draft: LoreEntry } | null>(null);
  const [dialogTab, setDialogTab] = useState<'simple' | 'advanced'>('simple');
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

  const exportFile = () => {
    const blob = new Blob([JSON.stringify({ entries }, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = editorChrome?.fileName ?? 'lorebook.json';
    a.click();
    URL.revokeObjectURL(a.href);
  };

  return (
    <>
      {editorChrome ? (
        <div className="row-actions" data-testid="lore-actions" style={{ flexWrap: 'wrap' }}>
          <button className="ghost" onClick={() => fileRef.current?.click()}>
            Import file
          </button>
          <button className="ghost" onClick={exportFile}>
            Export file
          </button>
          <button className="ghost" onClick={editorChrome.onFromCharacter}>
            From character
          </button>
          <button
            onClick={() => {
              setDialogTab('simple');
              setEditing({ index: null, draft: blankEntry() });
            }}
          >
            Add Entry
          </button>
        </div>
      ) : (
      <div className="row-label">
        <span>{title}</span>
        <div className="row-actions">
          <button className="ghost" onClick={() => fileRef.current?.click()}>
            Import JSON
          </button>
          <button className="ghost" onClick={add}>
            + Add entry
          </button>
        </div>
      </div>
      )}
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
      {note && (
        <p className="muted small" data-testid="lore-note">
          {note}
        </p>
      )}
      {entries.length === 0 && editorChrome && (
        <>
          <p className="muted">No lorebook entries yet</p>
          <p className="muted small">Add entries to inject context-aware world lore.</p>
        </>
      )}
      {entries.length === 0 && !editorChrome && <p className="muted">{emptyText}</p>}
      {editorChrome &&
        entries.map((entry, i) => (
          <div className="card lore-card" key={i} data-testid="lore-card">
            <div className="row-actions" style={{ alignItems: 'center' }}>
              <strong style={{ flex: 1, opacity: entry.enabled ? 1 : 0.55 }}>
                {entry.name.trim() || entry.key.split(',')[0]?.trim() || 'Untitled entry'}
              </strong>
              {entry.constant ? (
                <span className="gs-chip">Always Active</span>
              ) : (
                <span className="gs-chip">Depth {entry.stickyDepth}</span>
              )}
              <label
                className="tool-toggle"
                title={entry.enabled ? "Disable — entry won't be matched" : 'Enable — entry will match on its keys'}
              >
                <input
                  type="checkbox"
                  aria-label={entry.enabled ? 'Disable entry' : 'Enable entry'}
                  checked={entry.enabled}
                  onChange={(e) => update(i, { enabled: e.target.checked })}
                />
              </label>
              <button className="icon-btn" title="Edit entry" aria-label="Edit entry" onClick={() => {
                  setDialogTab('simple');
                  setEditing({ index: i, draft: { ...entry } });
                }}>
                ✏️
              </button>
              <button className="icon-btn" title="Delete entry" aria-label="Delete entry" onClick={() => remove(i)}>
                🗑
              </button>
            </div>
            {entry.key.trim() && !entry.constant && (
              <div className="tag-row">
                {entry.key
                  .split(',')
                  .map((k) => k.trim())
                  .filter(Boolean)
                  .map((k) => (
                    <span key={k} className="gs-chip">
                      {k}
                    </span>
                  ))}
              </div>
            )}
          </div>
        ))}
      {editing && (
        <div className="drawer-backdrop center" onClick={() => setEditing(null)}>
          <div
            className="modal lore-entry-modal"
            role="dialog"
            aria-label={editing.index == null ? 'Add Lorebook Entry' : 'Edit Lorebook Entry'}
            data-testid="lore-entry-dialog"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="row-actions" style={{ alignItems: 'center' }}>
              <h3 style={{ flex: 1, margin: 0 }}>
                {editing.index == null ? 'Add Lorebook Entry' : 'Edit Lorebook Entry'}
              </h3>
              <button
                className="ghost"
                aria-pressed={dialogTab === 'simple'}
                onClick={() => setDialogTab('simple')}
              >
                Simple
              </button>
              <button
                className="ghost"
                aria-pressed={dialogTab === 'advanced'}
                onClick={() => setDialogTab('advanced')}
              >
                Advanced
              </button>
            </div>
            <LoreEntryFields
              entry={editing.draft}
              update={(p) => setEditing((e) => (e ? { ...e, draft: { ...e.draft, ...p } } : e))}
              tab={dialogTab}
            />
            <div className="modal-actions">
              <button className="ghost" onClick={() => setEditing(null)}>
                Cancel
              </button>
              <button
                className="primary"
                onClick={() => {
                  const d = editing.draft;
                  onChange(
                    editing.index == null
                      ? [...entries, d]
                      : entries.map((x, j) => (j === editing.index ? d : x)),
                  );
                  setEditing(null);
                }}
              >
                {editing.index == null ? 'Add' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}
      {!editorChrome && entries.map((entry, i) => (
        <div className="card lore-edit" key={i}>
          <div className="row-actions">
            <button
              className="ghost"
              aria-pressed={!advancedOpen[i]}
              onClick={() => setAdvancedOpen((o) => ({ ...o, [i]: false }))}
            >
              Simple
            </button>
            <button
              className="ghost"
              aria-pressed={!!advancedOpen[i]}
              onClick={() => setAdvancedOpen((o) => ({ ...o, [i]: true }))}
            >
              Advanced
            </button>
            <button className="ghost" onClick={() => remove(i)}>
              Remove
            </button>
          </div>
          <LoreEntryFields
            entry={entry}
            update={(p) => update(i, p)}
            tab={advancedOpen[i] ? 'advanced' : 'simple'}
          />
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
