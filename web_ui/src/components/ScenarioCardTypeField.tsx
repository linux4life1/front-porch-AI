// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useId } from 'react';

export const scenarioSettingHelp = 'Leave blank to choose the setting in chat.';
export const scenarioOpeningHelp = 'With no greetings, the player speaks first.';
export const scenarioRulesHelp = 'Chat uses the first 2,000 characters. The card keeps the full text.';
export const scenarioNewChatHelp = 'New chats use changes to card type, setting, scene notes, narration style, facilitation rules and reply examples. Advanced prompts can affect existing chats.';
export const scenarioGroupScopeHelp = 'These edits apply only to this group member.';

export type CardType = 'character' | 'scenario' | 'unsupported';

export function ScenarioCardTypeField({ value, onChange }: {
  value: CardType;
  onChange: (value: 'character' | 'scenario') => void;
}) {
  const helpId = useId();
  return <>
    <label>
      Card type
      <select aria-describedby={helpId} value={value} disabled={value === 'unsupported'}
        onChange={(event) => onChange(event.target.value === 'scenario' ? 'scenario' : 'character')}>
        <option value="character">Character</option>
        <option value="scenario">Scenario</option>
        {value === 'unsupported' && <option value="unsupported">Unsupported card type</option>}
      </select>
    </label>
    <p className="muted small" id={helpId}>
      {value === 'unsupported'
        ? 'This card’s type is preserved. This version opens it as Character.'
        : value === 'scenario'
          ? 'Runs a scene without a primary character and leaves your choices to you.'
          : 'Plays a character in the story.'}
    </p>
  </>;
}
