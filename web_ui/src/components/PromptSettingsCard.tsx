// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The prompt family for web Settings, mirroring the desktop General tab:
// the Fallback system prompt slot with the Global prompt additions flat
// under it (prompt-picker SOW Phase 2 — one prompt family, one place),
// then the Group system prompt slot every group chat uses. Both slots pick
// from one shared pool of saved prompts.

import { PromptSlot, type BuiltInPrompt, type SavedPrompt } from './PromptSlot';

export function PromptSettingsCard({
  systemPrompt,
  systemPromptName,
  additionalSystemPrompt,
  additionalPostHistoryInstructions,
  groupSystemPrompt,
  groupSystemPromptName,
  builtInGroupSystemPrompt,
  builtInSystemPrompts,
  savedPrompts,
  patch,
}: {
  systemPrompt?: string;
  systemPromptName?: string | null;
  additionalSystemPrompt?: string;
  additionalPostHistoryInstructions?: string;
  groupSystemPrompt?: string;
  groupSystemPromptName?: string | null;
  builtInGroupSystemPrompt?: string;
  builtInSystemPrompts?: BuiltInPrompt[];
  savedPrompts?: SavedPrompt[];
  patch: (p: Record<string, unknown>) => void;
}) {
  if (systemPrompt === undefined) return null;
  const pool = savedPrompts ?? [];
  // A delete from either slot lets go of every slot that named that prompt.
  const onPool = (next: SavedPrompt[]) => {
    const has = (n?: string | null) => !!n && next.some((p) => p.name === n);
    patch({
      savedPrompts: next,
      ...(systemPromptName && !has(systemPromptName) ? { systemPromptName: null } : {}),
      ...(groupSystemPromptName && !has(groupSystemPromptName) ? { groupSystemPromptName: null } : {}),
    });
  };
  return (
    <section className="card" data-testid="prompt-settings-card">
      <h3>System prompts</h3>
      <PromptSlot
        testId="fallback-system-prompt"
        title="Fallback system prompt"
        helper="Used in one-to-one chats whose character card has no system prompt of its own. Group chats use the Group system prompt further down instead."
        label="Fallback system prompt"
        text={systemPrompt}
        name={systemPromptName}
        pool={pool}
        builtIns={builtInSystemPrompts ?? []}
        onChange={(text, name) => patch({ systemPrompt: text, systemPromptName: name })}
        onPool={onPool}
      />
      {additionalSystemPrompt !== undefined &&
        additionalPostHistoryInstructions !== undefined && (
          <div className="prompt-additions" data-testid="global-prompt-additions">
            <h4>Global prompt additions</h4>
            <p className="muted small">Extra instructions for every character and chat model. Leave blank to disable. Both fields support {'{{char}}'} and {'{{user}}'}. Use Save settings to apply changes.</p>
            <label>Additional system instructions
              <textarea rows={4} value={additionalSystemPrompt}
                onChange={(e) => patch({ additionalSystemPrompt: e.target.value })} />
            </label>
            <p className="muted small">Appended to the selected system prompt, including character and group prompts.</p>
            <label>Additional post-history instructions
              <textarea rows={4} value={additionalPostHistoryInstructions}
                onChange={(e) => patch({ additionalPostHistoryInstructions: e.target.value })} />
            </label>
            <p className="muted small">Appended after existing post-history instructions.</p>
          </div>
        )}
      <PromptSlot
        testId="group-system-prompt"
        title="Group system prompt"
        helper="Used in every group chat, unless that group has its own prompt in Edit group. Front Porch adds its own turn rules, and Director Mode's, on top either way."
        label="Group system prompt"
        text={groupSystemPrompt ?? ''}
        name={groupSystemPromptName}
        pool={pool}
        builtIns={builtInGroupSystemPrompt ? [{ label: 'Group default', text: builtInGroupSystemPrompt }] : []}
        blankIsBuiltIn
        onChange={(text, name) => patch({ groupSystemPrompt: text, groupSystemPromptName: name })}
        onPool={onPool}
      />
    </section>
  );
}
