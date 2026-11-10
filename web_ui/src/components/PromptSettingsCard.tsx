// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The prompt family for web Settings, mirroring the desktop General tab:
// the Fallback system prompt slot, the Group system prompt slot every group
// chat uses, and the Global prompt additions flat under them (Option A
// layout: one prompt family, 3 stacked cards). Both slots pick from one
// shared pool of saved prompts.

import { useRef } from 'react';
import { PromptSlot, type BuiltInPrompt, type SavedPrompt } from './PromptSlot';
import { insertPromptMacro } from './macroInsert';

function GlobalPromptAdditionsCard({
  additionalSystemPrompt,
  additionalPostHistoryInstructions,
  patch,
}: {
  additionalSystemPrompt: string;
  additionalPostHistoryInstructions: string;
  patch: (p: Record<string, unknown>) => void;
}) {
  const sysRef = useRef<HTMLTextAreaElement>(null);
  const postRef = useRef<HTMLTextAreaElement>(null);

  const insertSystemMacro = (macro: string) => {
    insertPromptMacro(sysRef.current, additionalSystemPrompt, macro, (next) => {
      patch({ additionalSystemPrompt: next });
    });
  };

  const insertPostMacro = (macro: string) => {
    insertPromptMacro(postRef.current, additionalPostHistoryInstructions, macro, (next) => {
      patch({ additionalPostHistoryInstructions: next });
    });
  };

  return (
    <section
      className="card prompt-additions prompt-additions-card"
      data-testid="global-prompt-additions"
    >
      <div className="prompt-slot-head">
        <h4>Global prompt additions</h4>
      </div>
      <p className="muted small">
        Extra instructions for every character and chat model. Leave blank to disable. Both
        fields support {'{{char}}'} and {'{{user}}'}. Use Save settings to apply changes.
      </p>

      <div className="prompt-field-group">
        <label htmlFor="add-system-instructions">Additional system instructions</label>
        <div className="macro-badges-row">
          <span className="macro-label">Available macros:</span>
          <button
            type="button"
            className="macro-chip"
            title="Inserts character name at runtime"
            onClick={() => insertSystemMacro('{{char}}')}
          >
            <code>{ '{{char}}' }</code>
            <span className="macro-desc">Character</span>
          </button>
          <button
            type="button"
            className="macro-chip"
            title="Inserts user persona name at runtime"
            onClick={() => insertSystemMacro('{{user}}')}
          >
            <code>{ '{{user}}' }</code>
            <span className="macro-desc">User</span>
          </button>
        </div>
        <textarea
          id="add-system-instructions"
          ref={sysRef}
          aria-label="Additional system instructions"
          rows={4}
          value={additionalSystemPrompt}
          onChange={(e) => patch({ additionalSystemPrompt: e.target.value })}
        />
        <p className="muted small">
          Appended to the selected system prompt, including character and group prompts.
        </p>
      </div>

      <div className="prompt-field-group">
        <label htmlFor="add-post-history">Additional post-history instructions</label>
        <div className="macro-badges-row">
          <span className="macro-label">Available macros:</span>
          <button
            type="button"
            className="macro-chip"
            title="Inserts character name at runtime"
            onClick={() => insertPostMacro('{{char}}')}
          >
            <code>{ '{{char}}' }</code>
            <span className="macro-desc">Character</span>
          </button>
          <button
            type="button"
            className="macro-chip"
            title="Inserts user persona name at runtime"
            onClick={() => insertPostMacro('{{user}}')}
          >
            <code>{ '{{user}}' }</code>
            <span className="macro-desc">User</span>
          </button>
        </div>
        <textarea
          id="add-post-history"
          ref={postRef}
          aria-label="Additional post-history instructions"
          rows={4}
          value={additionalPostHistoryInstructions}
          onChange={(e) => patch({ additionalPostHistoryInstructions: e.target.value })}
        />
        <p className="muted small">Appended after existing post-history instructions.</p>
      </div>
    </section>
  );
}

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
      ...(groupSystemPromptName && !has(groupSystemPromptName)
        ? { groupSystemPromptName: null }
        : {}),
    });
  };

  return (
    <div className="settings-group prompt-settings-group" data-testid="prompt-settings-card">
      <h4 className="settings-group-heading">Default prompts &amp; instructions</h4>
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
      <PromptSlot
        testId="group-system-prompt"
        title="Group system prompt"
        helper="Used in every group chat, unless that group has its own prompt in Group Settings. Front Porch adds its own turn rules, and Director Mode's, on top either way."
        label="Group system prompt"
        text={groupSystemPrompt ?? ''}
        name={groupSystemPromptName}
        pool={pool}
        builtIns={
          builtInGroupSystemPrompt
            ? [{ label: 'Group default', text: builtInGroupSystemPrompt }]
            : []
        }
        blankIsBuiltIn
        onChange={(text, name) => patch({ groupSystemPrompt: text, groupSystemPromptName: name })}
        onPool={onPool}
      />
      {additionalSystemPrompt !== undefined &&
        additionalPostHistoryInstructions !== undefined && (
          <GlobalPromptAdditionsCard
            additionalSystemPrompt={additionalSystemPrompt}
            additionalPostHistoryInstructions={additionalPostHistoryInstructions}
            patch={patch}
          />
        )}
    </div>
  );
}
