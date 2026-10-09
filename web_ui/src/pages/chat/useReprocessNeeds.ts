// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Derive Manual Reprocess modal props from the facade chips. The page only
// owns the open index; speakerName is the same needsSpeaker the facade sent,
// and feelingsSpeaker is set only when the facade offers a Feelings re-score.

import { type Message } from '../../components/chatTypes';

export function useReprocessNeeds(
  index: number | null,
  messages: Message[],
): { enabledNeeds: string[]; speaker: string; speakerName: string; feelingsSpeaker?: string } {
  if (index === null) {
    return { enabledNeeds: [], speaker: '', speakerName: '' };
  }
  const chips = messages[index]?.chips;
  const speaker = chips?.needsSpeaker ?? '';
  return {
    enabledNeeds: chips?.enabledNeeds ?? [],
    speaker,
    speakerName: speaker,
    feelingsSpeaker: chips?.feelingsReprocessable ? (chips.feelingsSpeaker ?? '') : undefined,
  };
}
