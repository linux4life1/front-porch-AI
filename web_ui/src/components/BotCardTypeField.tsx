// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useId } from 'react';

export const botScopeHelp = 'Describe the tasks this Bot handles and the context it should use.';
export const botOpeningHelp = 'With no greetings, you speak first.';
export const botInstructionsHelp = 'Chat uses the first 2,000 characters. The card keeps the full text.';
export const botNewChatHelp = 'New chats use changes to card type, scope, role, personality, behavior instructions and reply examples. Advanced prompts can affect existing chats.';
export const botGroupScopeHelp = 'These edits apply only to this group member.';

export type CardType = 'character' | 'bot' | 'unsupported';

export function BotCardTypeField({ value, onChange }: {
  value: CardType;
  onChange: (value: 'character' | 'bot') => void;
}) {
  const helpId = useId();
  return <>
    <label>
      Card type
      <select aria-describedby={helpId} value={value} disabled={value === 'unsupported'}
        onChange={(event) => onChange(event.target.value === 'bot' ? 'bot' : 'character')}>
        <option value="character">Character</option>
        <option value="bot">Bot</option>
        {value === 'unsupported' && <option value="unsupported">Unsupported card type</option>}
      </select>
    </label>
    <p className="muted small" id={helpId}>
      {value === 'unsupported'
        ? 'This card’s type is preserved. This version opens it as Character.'
        : value === 'bot'
          ? 'Speaks directly to you in its own voice.'
          : 'Plays a character in the story.'}
    </p>
  </>;
}
