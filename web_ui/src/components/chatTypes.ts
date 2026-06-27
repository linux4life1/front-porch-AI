// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared chat view-model types + the needs label map, extracted from ChatPage so
// the chat presentation components (message list, chips, insight panel) can share
// one source of truth without ChatPage growing past the file-size cap.

export interface Chips {
  bondDelta?: number;
  trustDelta?: number;
  arousalDelta?: number;
  emotionLabel?: string;
  bondReason?: string;
  trustReason?: string;
  timeSkipTo?: string;
  chanceTimeEvent?: string;
  // Tolerate the legacy int shape and the new {delta, reason} shape so a
  // frontend rebuild doesn't blank the Needs chips before the backend restarts.
  needsDeltas?: Record<string, number | { delta: number; reason?: string }>;
  needsReprocessable?: boolean;
  needsRevertable?: boolean;
}

export interface Message {
  index: number;
  sender: string;
  text: string;
  isUser: boolean;
  chips?: Chips;
  swipeCount?: number;
  swipeIndex?: number;
  hasThinking?: boolean;
  thinkingContent?: string;
  characterId?: string;
}

export interface Realism {
  bond: { score: number; tier: string; percent: number };
  longTerm: { score: number; tier: string; percent: number };
  trust: { level: number; tier: string; percent: number };
  emotion: string;
  emotionIntensity: string;
  mood: string;
  arousal: { level: number; tier: string };
  fixation: string;
  needsEnabled: boolean;
  needs: Record<string, number>;
}

export interface LoreEntry {
  key: string;
  name: string;
  isTriggered: boolean;
  constant: boolean;
}

export const NEED_LABELS: Record<string, string> = {
  hunger: 'Hunger',
  bladder: 'Bladder',
  energy: 'Energy',
  social: 'Social',
  fun: 'Fun',
  hygiene: 'Hygiene',
  comfort: 'Comfort',
};
