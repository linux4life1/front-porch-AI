// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GET /api/chat/state payload. Lives here so the session hook and the page
// share one type without importing ChatPage.

import { type CastMember } from '../../components/CastBar';
import {
  type ChatThemeOverrides,
  type LoreEntry,
  type Message,
  type Realism,
} from '../../components/chatTypes';

export interface ChatState {
  character: { name: string; id: string } | null;
  chatTitle?: string | null;
  sessionId: string | null;
  messages: Message[];
  isGenerating: boolean;
  isSettlingTurn?: boolean;
  isSendWaitingOnSettle?: boolean;
  isLoadingSession?: boolean;
  isBackfillingHistory?: boolean;
  hasOlderHistory?: boolean;
  isEvaluatingRealism?: boolean;
  isCheckingCompletion?: boolean;
  isProcessingGreeting?: boolean;
  isVerifyingRealism?: boolean;
  realismEvalText?: string;
  isGroupMode?: boolean;
  groupId?: string | null;
  realism?: Realism;
  lorebook?: LoreEntry[];
  loreTokens?: number;
  loreBudget?: number;
  loreOverflow?: string[];
  authorNote?: string;
  authorNoteDepth?: number;
  greetingIndex?: number;
  totalGreetings?: number;
  expressionLabel?: string;
  // Living Time §2 welcome-back banner (additive — absent on older facades;
  // null when off/under threshold). Coarse words only.
  absencePhrase?: string | null;
  summary?: string;
  cast?: CastMember[];
  guestActivity?: { status: string | null; isError: boolean; busy: boolean };
  pendingDetection?: string | null;
  // Chaos "Chance Time" park state: while pending, the engine is frozen waiting
  // for the user to accept their fate (event is pre-resolved server-side).
  chanceTime?: { pending: boolean; event?: string };
  // Crafted /image prompt parked for review (review setting on) — the modal
  // resolves it via POST /api/chat/image-review.
  imagePromptReview?: string;
  // Current model's tool-calling verdict (desktop sidebar pill parity);
  // retest via POST /api/chat/tool-test.
  toolSupport?: {
    state: string;
    testing: boolean;
    preferText?: boolean;
    paused?: boolean;
    checked?: boolean;
  };
  // Per-chat theme overrides (preset + font/color/background/border).
  themeOverrides?: ChatThemeOverrides;
  // Host LLM connection (additive — older desktops omit it).
  llmReady?: boolean;
}
