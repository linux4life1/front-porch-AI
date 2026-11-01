// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';

/// Per-turn mutable state for one `_generateResponse` run. It holds the
/// former locals of the single ~1.9k-line method so its phases (the prompt
/// assembler's blocks, plan, RAG and request in this directory; the stream
/// and post-generation parts of the chat service library) can pass them
/// along without changing behaviour. Never outlives the turn; never stored
/// on the chat service. Fields marked `late` are promotion workarounds (H4):
/// each is assigned unconditionally in the phase that produces it, and
/// reading one out of order is a loud `LateInitializationError` —
/// deliberate, not silent corruption, because the skeleton's phase-call
/// order is fixed.
class GenTurn {
  GenTurn({
    required this.mode,
    required this.guestSpeaker,
    required this.epoch,
    required this.autonomous,
    required this.directUserSend,
    this.forcedWebQuery,
    this.forcedWikiQuery,
  });

  final GenerationMode mode;
  final CharacterCard? guestSpeaker;
  final int epoch;
  final bool autonomous;

  /// Explicit allow-list bit for web search. False by default so every
  /// non-send generation path stays offline unless its caller proves it is
  /// the direct response to a newly appended user message.
  final bool directUserSend;

  /// Words the user named with `/search --` or the regenerate field.
  /// Null means the voluntary doorbell may still decide.
  final String? forcedWebQuery;

  /// Words the user named with `/wiki --` or the regenerate field.
  final String? forcedWikiQuery;

  /// One-shot regen director slip (clip + reason). Empty on every other path.
  String regenCritique = '';

  // ── entry / speaker pick (shell) ──
  late CharacterCard speakingCharacter;

  /// The group rotation before this turn picked its speaker. Put back when
  /// the turn ends before its reply bubble lands ([replyLanded]).
  TurnRotation? rotationBeforePick;
  bool replyLanded = false;
  late String userName;
  // Track original model for call mode swap/restore. Deliberately survives
  // outside the try/catch (H5): set in the request phase, read by the
  // stream-phase cancel path, postgen's restore, and the shell's catch —
  // constructing the carrier before the try satisfies that contract.
  String? originalModelName;

  // ── blocks phase → plan phase (block strings; the plan phase's macro pass
  // MUTATES most of them in place) ──
  late String systemPrompt;
  String loreBefore = '';
  String loreAfter = '';
  String loreAnTop = '';
  String loreAnBottom = '';
  String loreExTop = '';
  String loreExBottom = '';
  List<LoreDepthEntry> loreDepth = const [];
  late String personaBlock;
  late String userPersonaBlock;
  late String scenario;
  late String suffix;
  String mesExampleBlock = '';
  String speakerCardBlock = '';
  String toolRulesBlock = ''; // after-lookup lines; seat in plan_register

  /// Character Growth. After the transcript, not glued onto the persona,
  /// so a ring update does not rewrite the cached prompt head. Not a state
  /// zone member: Continue keeps it, the way the persona used to.
  String growthBlock = '';
  String postHistoryBlock = '';
  String authorNoteBlock = '';
  String summaryBlock = '';
  String journalBlock = '';
  Set<int> expandedJournalPositions = const {};

  /// Cued RAG / journal-cold query for this turn (emotion + fixation +
  /// top hot journal line + last words). Empty until the blocks phase.
  String ragQuery = '';

  /// Top hot journal line baked into [ragQuery] (re-composed after Continue pops).
  String ragHotJournalLine = '';

  /// Journal card contents used to drop RAG windows the diary already covers.
  List<String> journalCoverLines = const [];

  // ── plan phase → rag/request phases ──
  String history = '';

  /// Latest beat, cut off [history]; renders after the state zone.
  String latestTurn = '';
  int droppedMessages = 0;
  int historyBudget = 0;
  late PromptPlan plan;

  // ── rag phase → request phase ──
  String memoriesBlock = '';

  // ── rag phase → stream phase (metadata stamp) ──
  /// What retrieval found/dropped/injected this turn (rag_injection.dart
  /// wire shape), or null when retrieval never ran (nothing dropped, RAG
  /// off, or not operational). Stamped as `rag_receipt` on [streamTarget].
  Map<String, dynamic>? ragReceipt;

  /// Stamped as `search_receipt` when this turn ran a web_search lookup.
  Map<String, dynamic>? searchReceipt;

  /// Stamped as `wiki_receipt` when this turn opened the wiki.
  /// When only the wiki ran, [searchReceipt] is the same map so the chip shows.
  Map<String, dynamic>? wikiReceipt;

  /// Stamped as `tool_receipt` when this turn ran a user recipe card.
  Map<String, dynamic>? toolReceipt;

  /// Recipe cards loaded for this turn from `<library>/tools/`.
  List<UserToolCard> userToolCards = const [];

  // ── request phase → stream/postgen phases ──
  late List<String> stopList;
  late Stream<String> stream;
  late ChatGenerationSettings g2; // alias of _sessionGenSettings
  bool isLocalBackend = false;
  Timer? perfPoller; // cancelled at first-token, cancel-path, and postgen (H7)

  // ── stream phase → postgen phase ──
  String accumulatedResponse = '';
  late ChatMessage streamTarget;

  /// When this stream's `<think>` opened; null until it does.
  DateTime? thinkStartedAt;

  /// Ends this stream's think clock on [streamTarget], on every exit (done,
  /// Stop, throw). A think that never closed records the time spent so far,
  /// or the next group speaker's turn shows "Thinking…" on this bubble. The
  /// live start is this stream's alone: left on the message, a later swipe,
  /// Continue or Impersonate would time "Thinking" from it.
  void sealThinkClock() {
    streamTarget.thinkingStartTime = null;
    final started = thinkStartedAt;
    if (started == null || streamTarget.thinkingDurationMs > 0) return;
    final ms = DateTime.now().difference(started).inMilliseconds;
    streamTarget.thinkingDurationMs = ms <= 0 ? 1 : ms;
  }

  /// Pre-Continue body of the message being extended. Empty for non-Continue
  /// modes. [accumulatedResponse] is only the NEW tokens; the stream phase
  /// paints `glueContinueText(continuePrefix, tokens)` for display, and
  /// postgen must re-merge the same way before sanitize/persist or the
  /// bubble collapses to the continuation fragment alone (full-codebase
  /// audit 2026-08-11 P0). The glue inserts a word-break space when the
  /// prefix does not already end with whitespace (Discord 2026-08-15).
  String continuePrefix = '';
}
