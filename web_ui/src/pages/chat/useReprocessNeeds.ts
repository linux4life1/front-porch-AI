// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Derive Reprocess Needs modal props from the facade chips. The page only
// owns the open index; speakerName is the same needsSpeaker the facade sent.

import { type Message } from '../../components/chatTypes';

export function useReprocessNeeds(
  index: number | null,
  messages: Message[],
): { enabledNeeds: string[]; speaker: string; speakerName: string } {
  if (index === null) {
    return { enabledNeeds: [], speaker: '', speakerName: '' };
  }
  const speaker = messages[index]?.chips?.needsSpeaker ?? '';
  return {
    enabledNeeds: messages[index]?.chips?.enabledNeeds ?? [],
    speaker,
    speakerName: speaker,
  };
}
