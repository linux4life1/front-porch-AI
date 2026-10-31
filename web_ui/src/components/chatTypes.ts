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
  /** Why they felt it, filed with this reply (desktop: `emotion_cause`). */
  emotionCause?: string;
  /** Standing Mood: what they walked in carrying ("Came in …"). */
  moodStanding?: string;
  bondReason?: string;
  trustReason?: string;
  /** Why Lust moved this reply, in the character's words. */
  arousalReason?: string;
  timeSkipTo?: string;
  timePassed?: string;
  chanceTimeEvent?: string;
  searchQuery?: string;
  searchOk?: boolean;
  wikiQuery?: string;
  wikiOk?: boolean;
  toolName?: string;
  toolOk?: boolean;
  // Tolerate the legacy int shape and the new {delta, reason} shape so a
  // frontend rebuild doesn't blank the Needs chips before the backend restarts.
  needsDeltas?: Record<string, number | { delta: number; reason?: string }>;
  /** Short no-action turn: Needs ran, bars did not move. */
  needsUnaffected?: boolean;
  /** The bond/trust judge ran but its answer could not be read. */
  feelingsUnscored?: boolean;
  /** Chip text and tip for feelingsUnscored, from the desktop's constants. */
  feelingsUnscoredLabel?: string;
  feelingsUnscoredTip?: string;
  needsReprocessable?: boolean;
  /** Manual Reprocess can score this reply's feelings again (desktop resolver). */
  feelingsReprocessable?: boolean;
  /** Display name of the speaker a Feelings re-score would score. */
  feelingsSpeaker?: string;
  needsRevertable?: boolean;
  /** Enabled need keys for this speaker, from the desktop resolver. */
  enabledNeeds?: string[];
  /** Display name of the speaker the enabled set belongs to. */
  needsSpeaker?: string;
  /** Pockets & Wardrobe receipts ("picked up: car keys"), one chip each. */
  pocketChanges?: string[];
  /** Director verifier: 'accepted' | 'corrected'; passes = reprocess count. */
  directorStatus?: string;
  directorPasses?: number;
  directorReason?: string;
}

export interface Message {
  index: number;
  /** Stable row identity from the desktop object; falls back to index. */
  rowKey?: number;
  /** 0-based place in the whole chat (additive — older apps omit it). */
  position?: number;
  sender: string;
  text: string;
  isUser: boolean;
  chips?: Chips;
  swipeCount?: number;
  swipeIndex?: number;
  hasThinking?: boolean;
  /** The reply kept the prompt that produced it (Inspect prompt). */
  hasContext?: boolean;
  /** KoboldCpp kept the words this reply nearly used (Other words). */
  hasTokenAlts?: boolean;
  thinkingContent?: string;
  characterId?: string;
  /** Living Time §1 dream narration (additive — absent on older facades). */
  isDream?: boolean;
  /** A narrator's scene beat asked for while directing (`/narrate`). */
  isNarration?: boolean;
  /** Generated-image message: saved basename, served at /api/image/saved/<image>. */
  image?: string;
  /** The prompt that produced the image (tooltip / alt text). */
  imagePrompt?: string;
}

export interface Realism {
  /**
   * Whether the Realism Engine is switched on for this chat. Optional because
   * an older desktop build will not send it; treat a missing value as `true`
   * so those clients keep their current behaviour rather than going blank.
   */
  realismEnabled?: boolean;
  /** Sent only while Realism is off: false when Porch Life is what stops it. */
  realismAllowed?: boolean;
  /** Sent only while Realism is off: the chat's own switch. On (with Porch
   *  Life allowing it) is a change waiting for the reply to finish. */
  realismSwitch?: boolean;
  bond: { score: number; tier: string; percent: number };
  longTerm: { score: number; tier: string; percent: number };
  trust: { level: number; tier: string; percent: number };
  emotion: string;
  emotionIntensity: string;
  mood: string;
  /** Why the mood is what it is, and how many judge passes have kept it;
   *  `moodLine` is the one-line row the desktop shows. Absent on an older
   *  desktop build, which still sends `mood`. */
  emotionCause?: string;
  emotionHeld?: number;
  moodLine?: string;
  arousal: { level: number; tier: string };
  /** Afterglow runs in this chat: Porch Life (with 18+) allows it and the
   *  chat's own switch is on. The Lust line shows only then, as the desktop's
   *  Lust bar; an older server sends none and the line stays hidden. */
  lustOn?: boolean;
  /** The recovery countdown under the Lust line, in the desktop's words
   *  (this member's own in a group); empty or absent when none runs. */
  refractoryLabel?: string;
  /** A group member's own face label: the cache key for their portrait. */
  expressionLabel?: string;
  fixation: string;
  needsEnabled: boolean;
  needs: Record<string, number>;
  /** The engine's band cutoffs for the bar colours; absent on older servers. */
  needsUrgentAt?: number;
  needsCriticalAt?: number;
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
