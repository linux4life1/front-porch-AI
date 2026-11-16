// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A card saved elsewhere (the desktop's UI Settings writes a character's own
// chat colours to the card) reaches an open web chat: `library_changed` is one
// of the events that refetch the chat state, so each bubble's `look` (PR 8b)
// repaints. The earlier triggers stay.

import { expect, it } from 'vitest';
import { CHAT_REFRESH_EVENTS } from './useChatSession';

it('refetches the chat when a card changes in the library', () => {
  expect(CHAT_REFRESH_EVENTS.has('library_changed')).toBe(true);
  for (const e of ['chat_updated', 'generating', 'settings_changed']) {
    expect(CHAT_REFRESH_EVENTS.has(e), e).toBe(true);
  }
});
