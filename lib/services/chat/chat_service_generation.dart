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

part of '../chat_service.dart';

/// Absolute ceiling on the RAG memories block, applied on top of the
/// percentage budget (1:1's 10% / the group's configurable %). The block is
/// verbatim old transcript injected AFTER the history; past ~2,500 tokens
/// models start replaying it as if it were the current scene, so the cap
/// keeps large-context setups (10% of 32k = 3,200) under that line too.
const int kRagMemoryBudgetCapTokens = 1200;

/// User-facing notice for "managed backend stopped + auto-start off". Const
/// so [_abortIfBackendDown]'s dedupe can compare against the last message.
const _kBackendDownNotice =
    'Backend is not running. Start it in Settings → Backend, '
    "or enable 'Auto-start on chat open'.";

/// Per-turn mutable state for one `_generateResponse` run. Exists ONLY so the
/// phase methods in the `chat_service_generation_*.dart` sibling parts (the
/// god-file split, docs/design/god-file-elimination.md) can hold the former
/// locals of the single ~1.9k-line method without changing behaviour. Never
/// outlives the turn; never stored on ChatService. Fields marked `late` are
/// promotion workarounds (H4): each is assigned unconditionally in the phase
/// that produces it, and reading one out of order is a loud
/// `LateInitializationError` — deliberate, not silent corruption, because the
/// skeleton's phase-call order is fixed.
class _GenTurn {
  _GenTurn({
    required this.mode,
    required this.guestSpeaker,
    required this.epoch,
  });

  final GenerationMode mode;
  final CharacterCard? guestSpeaker;
  final int epoch;

  // ── entry / speaker pick (shell) ──
  late CharacterCard speakingCharacter;
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

  // ── request phase → stream/postgen phases ──
  late List<String> stopList;
  late Stream<String> stream;
  late ChatGenerationSettings g2; // alias of _sessionGenSettings
  bool isLocalBackend = false;
  Timer? perfPoller; // cancelled at first-token, cancel-path, and postgen (H7)

  // ── stream phase → postgen phase ──
  String accumulatedResponse = '';
  late ChatMessage streamTarget;

  /// Pre-Continue body of the message being extended. Empty for non-Continue
  /// modes. [accumulatedResponse] is only the NEW tokens; the stream phase
  /// paints `glueContinueText(continuePrefix, tokens)` for display, and
  /// postgen must re-merge the same way before sanitize/persist or the
  /// bubble collapses to the continuation fragment alone (full-codebase
  /// audit 2026-08-11 P0). The glue inserts a word-break space when the
  /// prefix does not already end with whitespace (Discord 2026-08-15).
  String continuePrefix = '';
}

/// The core response generation orchestrator (`_generateResponse`): speaker
/// selection, the single per-speaker realism eval trigger (group path), and
/// the six-phase turn pipeline (system prompt/lore/persona/scenario/Scene-
/// Guest/summary/Journal assembly → macro pass + PromptPlan registration +
/// history budget → RAG retrieval + joint budget → request dispatch →
/// streaming → post-generation Realism/Needs/Journal/Growth/TTS wiring).
/// Decomposed from a single ~1.9k-line method into sibling `chat/
/// chat_service_generation_*.dart` parts of this library (god-file split,
/// docs/design/god-file-elimination.md) — every phase method is the ORIGINAL
/// code moved verbatim (mechanical `x` → `t.x` carrier rename via [_GenTurn]
/// only). Zero behaviour change. See that doc's map for the full hazard
/// list (H1–H12) if you need to touch a phase boundary.
extension ChatServiceGeneration on ChatService {
  /// True when generation must not proceed: the managed local backend is not
  /// running and auto-start on chat open is off. Appends ONE system notice
  /// naming the toggle (deduped against the last message so group
  /// auto-advance and idle retries can't stack copies), so every entry point
  /// — send, regenerate, continue, swipe, group advance, impersonate — fails
  /// the same friendly way instead of a connection error or silent cancel.
  ///
  /// Deliberately does NOT _saveChat: the notice is transient status, and
  /// persisting here from inside _generateResponse would write the transcript
  /// mid-mutation for callers that pop a message before generating (regen
  /// popped the last AI reply, abort saved the hole — permanent data loss).
  /// Callers that pop MUST also run this check BEFORE their pop (regen paths
  /// do); this deep guard is the backstop for the non-mutating entries.
  Future<bool> _abortIfBackendDown() async {
    if (_llmProvider?.hasManagedProcess != true ||
        _storageService.autostartOnChatOpen ||
        _llmProvider?.hasAnyManagedProcessRunning == true) {
      return false;
    }
    if (_messages.isEmpty || _messages.last.text != _kBackendDownNotice) {
      _messages.add(
        ChatMessage(text: _kBackendDownNotice, sender: 'System', isUser: false),
      );
      notifyListeners();
    }
    return true;
  }

  Future<void> _generateResponse(
    GenerationMode mode, {
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
  }) async {
    if (await _abortIfBackendDown()) {
      // No turn will run — terminate BOTH live streams. The sentence stream
      // has no error sentinel: `call_overlay` closes its controller on
      // '__DONE__' alone, and `TtsService.speakStreaming` blocks in
      // `await for` until that close, so a silent bail freezes a voice call
      // on "Thinking…" with the mic never re-armed.
      _tokenBroadcast.add('__ERROR__');
      _sentenceBroadcast.add('__DONE__');
      return;
    }
    // regenerateLastMessage holds the settling flag; the finally restores it.
    final callerHeldSettling = _isPostGenerating;
    final epoch = ++_generationEpoch;
    _isGenerating = true;
    _generationProgress = 0.0;
    _tokensGenerated = 0;
    _maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _generationStartTime = DateTime.now();
    _generationPhase = GenerationPhase.preparing;
    _prefillStartTime = null;
    _lastPerfData = null;
    _sentenceBuffer = '';
    notifyListeners();

    final t = _GenTurn(mode: mode, guestSpeaker: guestSpeaker, epoch: epoch);

    try {
      final userName = _userPersonaService.persona.name;
      t.userName = userName;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (guestSpeaker != null) {
        // Scene Guest (Lite NPC) turn — stays in 1:1 (_activeGroup remains null),
        // the guest speaks in its own bubble. Carries NO Realism/Needs work
        // (see the guestSpeaker == null guards in the post-gen block below).
        speakingCharacter = guestSpeaker;
      } else if (_activeGroup != null) {
        speakingCharacter =
            (mode == GenerationMode.continue_ &&
                _messages.isNotEmpty &&
                !_messages.last.isUser)
            ? _groupCharacters.firstWhere(
                (c) => c.name == _messages.last.sender,
                orElse: () => _pickPresentGroupSpeaker(),
              )
            : (forceSpeaker ?? _pickPresentGroupSpeaker());
      } else {
        speakingCharacter = _activeCharacter!;
      }
      t.speakingCharacter = speakingCharacter;

      if (guestSpeaker == null &&
          _activeGroup != null &&
          mode != GenerationMode.continue_ &&
          forceSpeaker == null &&
          _groupSpeakerSkips(speakingCharacter)) {
        // Whole roster (or a forced @name) is Away / At work. Do not eat
        // the send: write a glance line. No reply to score, so the clock
        // takes the failure-drift step (bucket brigade still moves) and
        // Today is not rewritten.
        if (_clockRunning) {
          await _timeService.applyFailureDrift();
        }
        _messages.add(
          ChatMessage(
            text: _presenceSkipBanner(speakingCharacter),
            sender: 'System',
            isUser: false,
          ),
        );
        debugPrint(
          '[Presence] skip-turn ${speakingCharacter.name} — banner, no reply',
        );
        _isGenerating = false;
        _generationPhase = GenerationPhase.idle;
        await _saveChat();
        notifyListeners();
        return;
      }

      // Pin the realism speaker for the whole turn so prompt injection + decay
      // key on the character actually generating — not nextCharacter (the
      // *upcoming* speaker, null for random turn order). Scene guests carry no
      // realism, so they leave it null. Cleared in the finally below.
      _turnSpeakerIdForRealism = (_activeGroup != null && guestSpeaker == null)
          ? _getCharacterIdFromCard(speakingCharacter)
          : null;

      // SINGLE realism eval path (group trigger): the picked group member gets
      // their per-turn eval here, after selection, as it always has. The 1:1
      // host runs the SAME `_evaluateRealismForUpcomingSpeaker` from sendMessage
      // instead (fresh turns only) so regen — which calls _generateResponse
      // directly — does NOT re-evaluate and drift the host's realism. Lite Scene
      // Guests (guestSpeaker != null) carry no realism.
      if (guestSpeaker == null &&
          _activeGroup != null &&
          _realismActiveThisMode &&
          mode == GenerationMode.continue_) {
        // Continue extends the reply already on screen — the same exchange,
        // not a new one — so it must NOT re-run the dance: that charged the
        // speaker a second needs decay tick, a second bond/trust evaluation
        // and a second clock advance for one turn. The comment above spells
        // out the intent for 1:1 (its evaluation lives in sendMessage, so a
        // continuation cannot reach it); the group branch runs inside
        // _generateResponse and never got the matching guard.
        //
        // But it must still LOAD. The previous turn ended by saving this
        // speaker's scalars back to the map and restoring the pointer to
        // whoever was active before, so without this the continuation would be
        // written against another member's bond, trust and needs — the prompt
        // injection reads the live scalars. Load only: no evaluation, no
        // second charge, right member.
        final sid = _getCharacterIdFromCard(speakingCharacter);
        if (sid.isNotEmpty) _loadGroupRealismIntoScalars(sid);
      } else if (guestSpeaker == null &&
          _activeGroup != null &&
          _realismActiveThisMode) {
        await _evaluateRealismForUpcomingSpeaker(speakingCharacter);
        // Cancel-aborts-generation, group edition: the dance leaves the
        // cancel flag set for its caller (1:1's sendMessage has the twin
        // check). Consume it and abort the turn before any prompt is built.
        // The entry-state flags must be reset by hand — the normal clears
        // live in the completion path and the catch, which an early return
        // skips (the finally below only clears the speaker pin).
        if (_realismEvalCancelled) {
          _realismEvalCancelled = false;
          _isGenerating = false;
          _generationPhase = GenerationPhase.idle;
          _generationStartTime = null;
          await _saveChat();
          notifyListeners();
          return;
        }
      }

      // ── The six-phase turn pipeline (chat_service_generation_*.dart) ──
      // Fixed order — `late` carrier fields make an out-of-order call a loud
      // LateInitializationError, not silent corruption.
      await _assembleGenerationBlocks(t);
      await _buildGenerationPlan(t);
      await _retrieveGenerationMemories(t);
      await _dispatchGeneration(t);
      if (await _consumeGenerationStream(t)) {
        return; // user cancel: turn halted (H2)
      }
      await _finalizeGenerationTurn(t);
    } catch (e) {
      final wasCancelled = _cancelRequested;
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final treatAsCancel = wasCancelled || looksLikeBackendUnreachable(e);

      // User-initiated cancel (or forced client close) — keep the partial response, no error message
      if (treatAsCancel) {
        // Signal clean completion to SSE listeners
        _tokenBroadcast.add('__DONE__');
        if (_sentenceBuffer.trim().isNotEmpty) {
          _sentenceBroadcast.add(_sentenceBuffer.trim());
          _sentenceBuffer = '';
        }
        _sentenceBroadcast.add('__DONE__');

        // Restore original model if swapped for call mode
        if (t.originalModelName != null && _llmProvider != null) {
          _llmProvider!.openRouterService.configure(
            modelName: t.originalModelName,
          );
        }

        // Save the partial response so regen/continue work
        await _saveChat();
        notifyListeners();
        return;
      }

      // Build user-friendly error message (mapping lives in the pure leaf
      // generation_error_messages.dart, not a part — zero ChatService access).
      final errorMsg = friendlyGenerationError(e.toString());

      _messages.add(
        ChatMessage(text: errorMsg, sender: "System", isUser: false),
      );

      // Signal error to SSE listeners
      _tokenBroadcast.add('__ERROR__');
      // '__ERROR__' is a TOKEN-stream sentinel only. The sentence stream must
      // still be told the turn is over — its consumer (call_overlay →
      // TtsService.speakStreaming) closes on '__DONE__' and on nothing else,
      // so without this a non-socket failure (OpenRouter 429/402/5xx, a
      // malformed reply) leaves the voice call stuck on "Thinking…" forever.
      // The buffered fragment is dropped, not spoken: the reply the user gets
      // is the error banner, not a half sentence.
      _sentenceBuffer = '';
      _sentenceBroadcast.add('__DONE__');

      // Restore original model if swapped for call mode
      if (t.originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: t.originalModelName,
        );
      }

      notifyListeners();
    } finally {
      // The per-turn realism speaker pin lives only while we generate. Clear it
      // on every exit (normal completion, early return, or error) so the next
      // turn's pre-pick window (e.g. _applyMoodDecay) keeps its prior
      // nextCharacter-based behaviour instead of seeing a stale speaker.
      _turnSpeakerIdForRealism = null;
      // Settling over, on EVERY exit — restore the CALLER's hold (regen keeps
      // it raised across its swipe-merge); a latched flag would wedge input.
      _isPostGenerating = callerHeldSettling;
    }
  }

  /// Post-reply clock decide. Announced time was already in the prompt;
  /// this sets what the NEXT speaker is told. Continue is the same beat.
  /// Scene Guests carry no Realism/Needs but the clock is chat-scoped, so
  /// they tick time-only (no Today rewrite).
  Future<void> _maybeAdvanceStoryClockAfterReply(_GenTurn t) async {
    if (t.mode == GenerationMode.continue_) return;
    if (!_clockRunning) return;
    final msg = t.streamTarget;
    if (!msg.isUser) {
      // Stamp the LIVE swipe map. Writing `metadata` is a no-op for
      // regen when swipeMetadata[i] is already set — activeMetadata
      // returns that slot, not the legacy field.
      final existing = msg.activeMetadata;
      if (existing != null) {
        existing.putIfAbsent(
          'story_clock_before',
          () => _timeService.storyClockIso,
        );
      } else {
        msg.activeMetadata = {'story_clock_before': _timeService.storyClockIso};
      }
    }
    await _realismEvals.evaluatePhysicalStateCall(
      timeOnly: true,
      skipTodayEval: t.guestSpeaker != null,
    );
    if (t.guestSpeaker != null) {
      final named = clockNamedInReply(msg.text, _timeService.clock);
      if (named != null) await _timeService.applyReconciledClock(named);
    }
  }
}
