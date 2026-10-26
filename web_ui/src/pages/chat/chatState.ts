// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GET /api/chat/state payload. Lives here so the session hook and the page
// share one type without importing ChatPage.

import { type CastMember } from '../../components/CastBar';
import { type ToolSupport } from '../../components/ToolCallingPill';
import { type PromptSourceState } from '../../components/PromptSource';
import { type DirectorState, type ExitUndo } from '../../components/DirectorStrip';
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
  /** The group's stored lorebook could not be read (its entries are unused). */
  groupLorebookUnreadable?: boolean;
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
  // Director Mode and the open /exit UNDO (additive; absent on older apps).
  director?: DirectorState;
  exitUndo?: ExitUndo | null;
  // A reply stopped from the Realism overlay (additive). Stays until the chat
  // moves on or it is dismissed via POST /api/chat/stopped-reply/dismiss.
  stoppedReply?: { notice: string; canRetry: boolean } | null;
  pendingDetection?: string | null;
  pendingPicker?: { filter: string; full: boolean } | null;
  // Slice 6 (additive): a suggested scene move awaiting the author —
  // the PWA twin of the desktop confirm dialog. Answering is one POST
  // to /api/chat/place-move; the flag clears on the next snapshot.
  pendingPlaceMove?: { id: string; name: string } | null;
  // Slice 7 (additive): a proposed NAMED new place from the clock
  // judge's 'new' answer. Answered via POST /api/chat/place-mint.
  pendingMint?: { name: string; descriptor: string; settingName?: string } | null;
  // Chaos "Chance Time" park state: while pending, the engine is frozen waiting
  // for the user to accept their fate (event is pre-resolved server-side).
  chanceTime?: { pending: boolean; event?: string };
  // Crafted /image prompt parked for review (review setting on) — the modal
  // resolves it via POST /api/chat/image-review.
  imagePromptReview?: string;
  // Current model's tool-calling verdict (desktop sidebar pill parity);
  // retest via POST /api/chat/tool-test.
  toolSupport?: ToolSupport;
  // Per-chat theme overrides (preset + font/color/background/border).
  themeOverrides?: ChatThemeOverrides;
  // The Ambient Stage: the story's weather as colour strings the chat view
  // paints behind the bubbles (additive; null or absent means no scene).
  scene?: unknown;
  // Per-chat system prompt source (1:1 only) and the new-chat picker's
  // prompts while a new chat waits on it (additive; omitted in groups).
  promptSource?: PromptSourceState;
  // Host LLM connection (additive — older desktops omit it).
  llmReady?: boolean;
  // Why the host's start of KoboldCpp was refused, in place of "No API
  // connection" (additive; omitted when there is nothing to say).
  llmHint?: string | null;
  // Named lookups the regenerate dialog may offer.
  lookupSources?: { web?: boolean; wiki?: boolean };
}
