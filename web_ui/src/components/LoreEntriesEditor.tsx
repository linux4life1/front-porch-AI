// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared lorebook entry editor used by the create wizard and the character edit
// page so both author lore identically. Each entry: name, trigger keywords
// (comma-separated), content, and an "always active" (constant) flag.

export interface LoreEntry {
  name: string;
  key: string;
  content: string;
  constant: boolean;
}

export function LoreEntriesEditor({
  entries,
  onChange,
}: {
  entries: LoreEntry[];
  onChange: (entries: LoreEntry[]) => void;
}) {
  const add = () => onChange([...entries, { name: '', key: '', content: '', constant: false }]);
  const remove = (i: number) => onChange(entries.filter((_, j) => j !== i));
  const update = (i: number, patch: Partial<LoreEntry>) => {
    const next = [...entries];
    next[i] = { ...next[i], ...patch };
    onChange(next);
  };

  return (
    <>
      <div className="row-label">
        <span>Lorebook entries</span>
        <button className="ghost" onClick={add}>+ Add entry</button>
      </div>
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
          <textarea
            placeholder="Lore content"
            rows={3}
            value={entry.content}
            onChange={(e) => update(i, { content: e.target.value })}
          />
          <div className="row-label">
            <label className="tool-toggle">
              <span>Always active</span>
              <input
                type="checkbox"
                checked={entry.constant}
                onChange={(e) => update(i, { constant: e.target.checked })}
              />
            </label>
            <button className="ghost" onClick={() => remove(i)}>Remove</button>
          </div>
        </div>
      ))}
    </>
  );
}
