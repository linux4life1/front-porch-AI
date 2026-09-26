// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Derive Reprocess Needs modal props from the facade chips. The page only
// owns the open index; this read is the same one ChatPage used to inline.

import { type Message } from '../../components/chatTypes';

export function useReprocessNeeds(
  index: number | null,
  messages: Message[],
  fallbackName?: string,
): { enabledNeeds: string[]; speaker: string; speakerName: string } {
  if (index === null) {
    return { enabledNeeds: [], speaker: '', speakerName: '' };
  }
  const chips = messages[index]?.chips;
  const speaker = chips?.needsSpeaker ?? '';
  return {
    enabledNeeds: chips?.enabledNeeds ?? [],
    speaker,
    speakerName: chips?.needsSpeaker ?? fallbackName ?? '',
  };
}
