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
  /** Living Time §1 dream narration (additive — absent on older facades). */
  isDream?: boolean;
  /** Generated-image message: saved basename, served at /api/image/saved/<image>. */
  image?: string;
  /** The prompt that produced the image (tooltip / alt text). */
  imagePrompt?: string;
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
  /** Legacy sticky-turns countdown (turns the entry stays active). */
  remainingDepth?: number;
  /** ST timed effects — messages of sticky/cooldown remaining (timer pills). */
  stickyLeft?: number;
  cooldownLeft?: number;
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

/** Per-chat theme overrides (mirrors ChatThemeOverrides model). Null = use preset default. */
export interface ChatThemeOverrides {
  themeId?: string | null;
  fontFamily?: string | null;
  userBubbleColor?: string | null;
  userTextColor?: string | null;
  aiBubbleColor?: string | null;
  aiTextColor?: string | null;
  dialogueColor?: string | null;
  actionColor?: string | null;
  backgroundKey?: string | null;
  borderStyle?: string | null;
  borderColor?: string | null;
}

/** A theme preset as returned by the desktop (mirrors ChatThemePreset). */
export interface ChatThemePreset {
  id: string;
  displayName: string;
  description: string;
  defaultUserBubbleColor: number;
  defaultUserTextColor: number;
  defaultAiBubbleColor: number;
  defaultAiTextColor: number;
  defaultDialogueColor: number;
  defaultActionColor: number;
  defaultBorderColor?: number;
  defaultFontFamily: string;
  defaultBackgroundKey: string;
  defaultBorderStyle: string;
}
