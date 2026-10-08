// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { filterChatSources, type ChatSourceRow } from './ChatSourcePicker';
import { adoptChat, emptyDraft, lengthWarning, suggestedLengthForChat, type ChatSource } from './draft';

const row = (character_name: string, session_name: string): ChatSourceRow => ({
  character_id: character_name, character_name, session_id: `${character_name}-${session_name}`,
  session_name, date: '2026-10-01T00:00:00.000', message_count: 40, short: false,
});

const rows = [row('Mira Vale', 'The lighthouse'), row('Dov Marsh', 'Letters'), row('Mira Vale', 'Second winter')];

describe('filterChatSources', () => {
  it('returns everything for an empty search', () => {
    expect(filterChatSources(rows, '  ')).toHaveLength(3);
  });

  it('matches the character name, ignoring case', () => {
    expect(filterChatSources(rows, 'mira').map((r) => r.session_name)).toEqual(['The lighthouse', 'Second winter']);
  });

  it('needs every word, across character and chat name', () => {
    expect(filterChatSources(rows, 'vale winter').map((r) => r.session_name)).toEqual(['Second winter']);
    expect(filterChatSources(rows, 'dov winter')).toHaveLength(0);
  });
});

describe('fitting the length to a faithful chat', () => {
  const chat = (messageCount: number, faithful = true): ChatSource =>
    ({ characterId: 'c1', characterName: 'Mira', sessionId: 's1', messageCount, faithful });

  it('a small chat starts on the shortest length', () => {
    expect(suggestedLengthForChat(13)).toBe('Short');
    expect(suggestedLengthForChat(150)).toBe('Standard');
    expect(adoptChat(emptyDraft(), chat(13), 'Sam').proseLength).toBe('Short');
    expect(adoptChat(emptyDraft(), chat(300), 'Sam').proseLength).toBe('Standard');
  });

  it('keeps a length that was already chosen', () => {
    expect(adoptChat({ ...emptyDraft(), proseLength: 'Epic' }, chat(13), 'Sam').proseLength).toBe('Epic');
  });

  it('warns when the chat cannot fill the length, in plain words', () => {
    const d = adoptChat(emptyDraft(), chat(13), 'Sam');
    expect(lengthWarning(d)).toContain('30,000-word novella');
    expect(lengthWarning({ ...d, proseLength: 'Standard' })).toContain('13 messages');
    expect(lengthWarning({ ...d, proseLength: 'Standard' })).toContain('mostly invented');
  });

  it('says nothing for a big chat, an unknown size, or "Inspired by"', () => {
    expect(lengthWarning(adoptChat(emptyDraft(), chat(300), 'Sam'))).toBeNull();
    expect(lengthWarning({ ...adoptChat(emptyDraft(), chat(0), 'Sam'), proseLength: 'Epic' })).toBeNull();
    expect(lengthWarning({ ...adoptChat(emptyDraft(), chat(13, false), 'Sam'), proseLength: 'Epic' })).toBeNull();
  });
});
