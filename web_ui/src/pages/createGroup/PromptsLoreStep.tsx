// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New group, Prompts & Lore: the two optional extras on one page, as on the
// desktop. The group and per-member system prompts, then the group lorebook
// and the Inherit switch. Web twin of GroupPromptsLoreStep.

import type { GroupDraft, LoreDraft } from './groupDraft';

const BLANK_ENTRY: LoreDraft = { name: '', keys: '', content: '', constant: false };

export function PromptsLoreStep({
  draft,
  set,
  members,
}: {
  draft: GroupDraft;
  set: (patch: Partial<GroupDraft>) => void;
  members: { id: string; name: string }[];
}) {
  const setEntry = (i: number, patch: Partial<LoreDraft>) =>
    set({ groupLore: draft.groupLore.map((e, j) => (j === i ? { ...e, ...patch } : e)) });

  return (
    <div className="cg-config">
      <p className="muted small">Both are optional. Skip ahead if the cards already say enough.</p>
      <label className="cg-field">
        <span className="cg-field-label">Group System Prompt</span>
        <textarea
          rows={3}
          value={draft.systemPrompt}
          placeholder="Blank uses the Group system prompt in Settings"
          onChange={(e) => set({ systemPrompt: e.target.value })}
        />
      </label>
      <h4 className="section-label">Per-member prompt overrides</h4>
      {members.map((m) => (
        <label className="cg-field" key={m.id}>
          <span className="cg-field-label">{m.name}</span>
          <textarea
            rows={2}
            value={draft.memberPrompts[m.id] ?? ''}
            placeholder="Extra instructions only for this character in this group"
            onChange={(e) => set({ memberPrompts: { ...draft.memberPrompts, [m.id]: e.target.value } })}
          />
        </label>
      ))}

      <div className="gw-row">
        <h4 className="section-label">Group Lorebook</h4>
        <button
          className="small"
          data-testid="group-lore-add"
          onClick={() => set({ groupLore: [...draft.groupLore, BLANK_ENTRY] })}
        >
          ＋ Add Entry
        </button>
      </div>
      {draft.groupLore.length === 0 && (
        <p className="muted small">No group lore entries yet. These take highest priority in prompts.</p>
      )}
      {draft.groupLore.map((e, i) => (
        <div className="gs-panel gw-member" key={i} data-testid={`group-lore-entry-${i}`}>
          <div className="gw-row">
            <input
              value={e.name}
              placeholder="Name"
              aria-label="Entry name"
              onChange={(ev) => setEntry(i, { name: ev.target.value })}
            />
            <button
              className="small ghost"
              onClick={() => set({ groupLore: draft.groupLore.filter((_, j) => j !== i) })}
            >
              Delete
            </button>
          </div>
          <label className="tool-toggle">
            <span>Always Active</span>
            <input
              type="checkbox"
              checked={e.constant}
              onChange={(ev) => setEntry(i, { constant: ev.target.checked })}
            />
          </label>
          {!e.constant && (
            <input
              value={e.keys}
              placeholder="Keys, separated by commas"
              aria-label="Entry keys"
              onChange={(ev) => setEntry(i, { keys: ev.target.value })}
            />
          )}
          <textarea
            rows={3}
            value={e.content}
            placeholder="What the model should know"
            aria-label="Entry content"
            onChange={(ev) => setEntry(i, { content: ev.target.value })}
          />
        </div>
      ))}
      <label className="tool-toggle">
        <span>Inherit character &amp; world lorebooks</span>
        <input
          type="checkbox"
          checked={draft.inheritCharacterLorebooks}
          onChange={(ev) => set({ inheritCharacterLorebooks: ev.target.checked })}
        />
      </label>
      <p className="muted small">
        When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.
      </p>
    </div>
  );
}
