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
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/services/expression_classifier.dart'; // top-level for ExpressionClassifierService type in @Dep shim (pre-existing)
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/needs_impact_evaluator.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/expression_classifier.dart'; // leaf for ExpressionService (post-extraction)
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/lorebook_scanner.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/author_note_builder.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/chaos_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/needs_injection.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/chat/objective_proposal.dart';
import 'package:front_porch_ai/services/chat/summary_service.dart';
import 'package:front_porch_ai/services/chat/fact_extraction.dart';
import 'package:front_porch_ai/services/chat/evolution_service.dart';
import 'package:drift/drift.dart' as drift;

// Internal flag to signal a cancellation request for realism evaluation.
// This is a file-scope flag to avoid needing to thread state through the
// entire class in this patch, and is reset once the interruption is surfaced
// to the UI.
bool _realismEvalCancelled = false;

// GBNF grammar support for Realism Engine evals (incl. Needs simulation) removed
// in the 0.9.8 clean port. All JSON outputs now rely on regex extraction + stop
// sequences inside _fireLLMEval (no _buildKoboldGrammar, no _kGbnf* consts).

class ChatService extends ChangeNotifier {
  final KoboldService _koboldService;
  final UserPersonaService _userPersonaService;
  final StorageService _storageService;
  final WorldRepository _worldRepository;
  late AppDatabase _db;
  LLMProvider? _llmProvider;
  CharacterRepository? _characterRepository;
  TtsService? _ttsService;
  MemoryService? _memoryService;

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without constructing a full
  /// LLMProvider (heavy deps). Used by chat_service_*_test.dart and
  /// chat_service_realism_engine_test.dart (the new real-engine suite).
  @visibleForTesting
  LLMService? testLlmServiceOverride;
  @visibleForTesting
  bool testIsLocalOverride = false;

  // Action suggestions
  List<String> _suggestedActions = [];
  bool _isGeneratingActions = false;
  List<String> get suggestedActions => _suggestedActions;
  bool get isGeneratingActions => _isGeneratingActions;

  // Objective/quest system
  List<Objective> _activeObjectives = [];
  int _messagesSinceLastCheck = 0;
  bool _isCheckingCompletion =
      false; // god-side secondary runtime flag for objective_proposal leaf's get/setIsChecking (early guard in check); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths (like _activeObjectives + _messagesSinceLastCheck) to prevent permanent skip of future task checks after in-flight reset; see CLAUDE.md "keep reset blocks in sync" + "incomplete zeroing..." (leaves incl fact/evo/verif + needs_impact etc) + " ; no extra mutable scalar; live read from frontPorch under impersonation)" + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)").
  bool _isNewChat = false;

  // Central post-dispose guard (re-introduced per PR #47 rec 2 for prod stability + test flake).
  // Protects *all* async-await-DB-then-notifyListeners patterns and any residual
  // fire-and-forget / microtask paths (e.g. unawaited objective loads, realism evals,
  // summary/fact/evo periodic, set* after rapid close/switch). Overrides ensure
  // no "A ChatService was used after being disposed" or channel errors.
  // Complements the "Awaited (was fire-and-forget)" at setActiveCharacter:2205;
  // see also _loadActiveObjectives and keep-reset sites. 0 new god private _ methods.
  bool _disposed = false;

  List<Objective> get activeObjectives => _activeObjectives;
  Objective? get primaryObjective =>
      _activeObjectives.where((o) => o.isPrimary).firstOrNull;
  List<Objective> get secondaryObjectives =>
      _activeObjectives.where((o) => !o.isPrimary).toList();

  List<Map<String, dynamic>> tasksForObjective(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  CharacterCard? _activeCharacter;
  final List<ChatMessage> _messages = [];
  Future<void> _saveChain = Future.value();
  Map<String, dynamic>?
  _pendingRealismMetadata; // stores deltas for the next generation
  bool _isGenerating = false;
  // True while a forked-in character's custom entrance sequence is running
  // (fire-and-forget after forkToGroupChat). Blocks user-triggered turns so the
  // one-shot _entranceDirective can't be consumed/overwritten by a racing user
  // turn. (Follow-up: pass the directive as a local into _generateResponse to
  // drop the shared field entirely.)
  bool _entrancesInFlight = false;
  bool _isLoadingSession = false;
  bool _cancelRequested = false;
  int _generationEpoch = 0;
  String? _currentSessionId;
  double _generationProgress = 0.0;
  int _tokensGenerated = 0;
  int _maxTokens = 0;
  DateTime? _generationStartTime;
  bool _isBuffering = false;
  GenerationPhase _generationPhase = GenerationPhase.idle;
  DateTime? _prefillStartTime; // When we entered prefill (for elapsed timer)
  int _prefillPromptTokens =
      0; // Estimated prompt token count for progress display
  Map<String, dynamic>? _lastPerfData; // Cached KoboldCPP perf data
  final List<String> _tokenBuffer = [];
  Timer? _drainTimer;
  int _displayedTokenCount = 0;
  final List<DateTime> _tokenTimestamps =
      []; // Rolling window for TPS measurement

  // ── Web SSE token broadcast ──
  // External consumers (e.g. WebChatBridge) listen to this for real-time token streaming.
  final StreamController<String> _tokenBroadcast =
      StreamController<String>.broadcast();
  Stream<String> get tokenStream => _tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  final StreamController<String> _sentenceBroadcast =
      StreamController<String>.broadcast();
  Stream<String> get sentenceStream => _sentenceBroadcast.stream;
  String _sentenceBuffer = ''; // accumulates tokens until a sentence boundary

  /// Whether the app is in voice call mode (auto-disables reasoning for lower latency).
  bool _callMode = false;
  bool get callMode => _callMode;
  set callMode(bool value) {
    _callMode = value;
    notifyListeners();
  }

  // ── Group chat state (owned by GroupTurnManager) ──
  GroupTurnManager? _groupManager;

  // Wired for decoupled group member loading (so setActiveGroup works even if caller
  // doesn't explicitly pass groupRepo every time). Set from main.dart provider setup.
  GroupChatRepository? _groupChatRepository;

  // One-shot hidden directive for a forked-in character's custom entrance
  // (Direction mode). Injected into the prompt, consumed on the next generation;
  // the forced-speaker side is handled by GroupTurnManager.setNextSpeaker.
  String? _entranceDirective;

  // ── Clean delegation layer (GroupTurnManager is the real owner) ────────
  // These keep the rest of the (very large) file readable while we finish
  // the migration. All group state now lives in _groupManager.
  GroupChat? get _activeGroup => _groupManager?.activeGroup;
  List<CharacterCard> get _groupCharacters =>
      _groupManager?.characters ?? const <CharacterCard>[];
  bool get _observerMode => _groupManager?.observerMode ?? false;
  set _observerMode(bool value) {
    _groupManager?.setObserverMode(value);
  }

  bool get _autoPlayActive => _groupManager?.autoPlayActive ?? false;
  set _autoPlayActive(bool value) {
    if (value) {
      _groupManager?.startAutoPlay();
    } else {
      _groupManager?.stopAutoPlay();
    }
  }

  double get directorDelaySec => _groupManager?.directorDelaySec ?? 15.0;
  set directorDelaySec(double value) {
    if (_groupManager != null) {
      _groupManager!.directorDelaySec = value;
    }
  }

  /// Per-character realism / needs / state for group chats.
  /// Keyed by stable charId. Populated from the hidden checkpoint.
  Map<String, Map<String, dynamic>> _groupRealism = {};

  /// Per-character Author's Notes for group chats (independent of group-level _authorNote).
  /// Keyed by stable charId (from _getCharacterIdFromCard). Populated from the
  /// (legacy comment — now persisted via sessions.group_realism_state column)
  Map<String, String> _groupAuthorNotes = {};
  Map<String, int> _groupAuthorNoteStrengths = {};

  /// Per-character system prompts scoped to the *current group only*.
  /// These are completely independent of each character's normal `systemPrompt`
  /// (the one used in 1:1 chats). When present and non-empty for the speaking
  /// character, they take full precedence over the character's card-level prompt
  /// inside this group. Now persisted via the sessions.group_realism_state column.
  Map<String, String> _groupCharacterSystemPrompts = {};

  /// Per-character objectives when in group mode.
  /// Each member carries their own independent personal objectives/tasks.
  /// Keyed by stable charId. Stored inside the group state JSON for now
  /// (consistent with other per-char group data like realism/needs).
  Map<String, List<Objective>> _groupObjectives = {};

  /// Returns the personal objectives for a specific character when in group mode.
  /// Falls back to the global list for 1:1 or when no per-char data exists yet.
  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) {
    if (_activeGroup == null) return _activeObjectives;
    final id = _getCharacterIdFromCard(character);
    return _groupObjectives[id] ?? const <Objective>[];
  }

  /// Returns all currently active lorebook entries (enabled + (triggered or constant))
  /// for the active group context. Includes:
  /// - Group-level lorebook
  /// - Lorebooks from worlds attached to the group
  /// - Per-character lorebooks (and their worlds) if `inheritCharacterLorebooks` is true
  ///
  /// This is intended for UI display (e.g. sidebar) to show what lore is currently "in play".
  List<LorebookEntry> getActiveGroupLoreEntries() {
    final result = <LorebookEntry>[];
    if (_activeGroup == null) return result;

    final inherit = _activeGroup!.inheritCharacterLorebooks;

    // 1. Group-level lorebook
    if (_activeGroup!.groupLorebook.isNotEmpty) {
      try {
        final json = jsonDecode(_activeGroup!.groupLorebook);
        final gl = Lorebook.fromJson(json as Map<String, dynamic>);
        result.addAll(
          gl.entries.where((e) => e.enabled && (e.isTriggered || e.constant)),
        );
      } catch (_) {}
    }

    // 2. Group-attached worlds
    for (final wid in _activeGroup!.worldIds) {
      final world = _worldRepository.worlds
          .where((w) => w.name == wid)
          .firstOrNull;
      if (world != null) {
        result.addAll(
          world.lorebook.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          ),
        );
      }
    }

    // 3. Per-character (and their worlds) if inheriting
    if (inherit) {
      for (final ch in _groupCharacters) {
        if (ch.lorebook != null) {
          result.addAll(
            ch.lorebook!.entries.where(
              (e) => e.enabled && (e.isTriggered || e.constant),
            ),
          );
        }
        for (final wName in ch.worldNames) {
          final world = _worldRepository.worlds
              .where((w) => w.name == wName)
              .firstOrNull;
          if (world != null) {
            result.addAll(
              world.lorebook.entries.where(
                (e) => e.enabled && (e.isTriggered || e.constant),
              ),
            );
          }
        }
      }
    }

    // Deduplicate by content to avoid showing the exact same lore text multiple times
    final seen = <String>{};
    return result.where((e) => seen.add(e.content)).toList();
  }

  // RAG settings for the active group (stored in the hidden checkpoint, no DB schema change)
  bool _groupRagEnabled = true;
  int _groupRetrievalCount = 8;
  double _groupMemoryBudgetPercent = 10.0;
  Map<String, double> _groupCharacterRAGPriorities = {};

  // Director Mode state is now owned by _groupManager when active.
  // The public getters below delegate to it.
  // ── Author's Note ──
  String _authorNote = '';
  int _authorNoteStrength = 4;

  // ── Chat Summary ──
  String _summary = '';
  int _summaryLastIndex = 0;
  bool _summaryPaused =
      false; // secondary runtime flag (like _isSummaryGenerating); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths to prevent leak of pause state across contexts (see CLAUDE.md keep-sync + incomplete zeroing (simple authority; sim reason kept)).
  bool _isSummaryGenerating = false;

  // ── Realism Mode ──
  bool _realismEnabled = false; // master toggle
  bool _isEvaluatingRealism = false;
  bool _isCancellingRealismEval = false;
  bool _isProcessingGreeting =
      false; // true while post-greeting baseline eval runs
  bool _greetingEvalPending =
      false; // greeting placed but baseline eval not yet run
  String _realismEvalStreamText = '';

  // Verifier phase coordination (god-owned for overlay + chips; leaf is stateless/prompt+rule).
  // Set around verify calls (via thin cb from leaves) so "🕵️ Verifying Realism output (pass X/Y)" shows
  // using the *exact same* overlay widgetry. 0 new void _ privates.
  bool _isVerifyingRealism = false;
  int _verificationPass = 0;
  int _verificationMaxPasses = 1;
  // Debounce timer — batches rapid per-chunk notifyListeners() calls during
  // eval streaming into a single rebuild every 150 ms. Without this, a
  // 40-token JSON response fires 40+ notifyListeners() calls and widgets that
  // are mid-deactivation throw "Looking up a deactivated widget's ancestor".
  Timer? _evalChunkTimer;

  // Short-term mood (counter only; decay logic for affection/short-term relationship
  // moved to RelationshipService; moodDelta resets kept here for snapshot/regen parity).
  int _moodDecayCounter = 0;

  // Emotional state
  String _characterEmotion = '';
  String _emotionIntensity = ''; // mild/moderate/strong

  // Expression images + classification (extracted to ExpressionService in chat/expression_classifier.dart).
  // See CLAUDE.md keep-sync + incomplete zeroing now complete + buffer removal + authority (live ext) at all sites + both startNew. (thins only)

  // Passage of time (core state + advance/nudge/OOC/resolve/reset/seed/load logic extracted to TimeService).
  // See CLAUDE.md keep-sync/incomplete zeroing/buffer removal/authority (live ext). Service owned.
  // god thins to delegation + 5 @Deprecated shims. 0 new private methods added in god for time.
  // time injection only thin wrapper here; full in step8. (cross-ref setActiveCharacter:1572 etc)

  // NSFW cooldown & lust (core state + tier calc + reset/seed/load/restore + group per-char scalars
  // + applyClimax/decrement extracted to NsfwService).
  // See keep reset + zeroing + buffer removal + authority (simple) in CLAUDE.md.
  // cooldown mutations, arousal, and helpers now owned by the service; god thins to delegation
  // + 5 @Deprecated shims. 0 new private methods added in god for nsfw.
  // _runPostGenNeedsChecks thin to needs_impact_evaluator (cross-ref setActiveCharacter:1572 etc; see CLAUDE.md for keep-sync).

  // ── Chaos Mode / Chance Time (core state extracted) ──────────────────────
  // _chaosModeEnabled / _chaosNsfwEnabled / _chaosPressure / _pendingChaosInjection / _chaosEventDelivered
  // now owned by _chaosModeService. The two UI coordination flags below stay in god
  // (cross widget boundary for overlay + send pause).
  String?
  _pendingChanceTimeEvent; // set when wheel lands; cleared after UI reads it
  bool _chanceTimePendingTrigger =
      false; // true for one cycle to pop the overlay

  // ── Sims/Needs Simulation (extracted) + Needs Impact Evaluator ──
  // Straight decay ticks in _needsSimulation; model deltas (+ optional Director review when authority) in _needsImpactEvaluator.
  // See CLAUDE.md for full reset keep-sync + "incomplete zeroing now complete" + buffer removal + authority decision (simple model+Director path).
  bool _needsSimEnabled = false;
  bool _enjoysLowHygiene =
      false; // inversion for hygiene (enjoys being dirty/sweaty/musky)

  Map<String, int> _groupDecayRates = {};
  Map<String, int> get groupDecayRates => _groupDecayRates;

  // Forwarding for critical threshold (moved to NeedsSimulation after buffer removal; UI + cards still reference the old ChatService surface)
  static int get needCriticalThreshold => NeedsSimulation.needCriticalThreshold;

  // ── Passage of time (extracted to TimeService) ───────────────────────────
  // (Declared early among late finals for init safety because needs/others close over its getters via cbs.
  // Logically added "after the other late finals" per extraction sequence; 0 new god privates.)
  late final _timeService = TimeService(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    onSetPendingRealismMetadata: (key, value) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata![key] = value;
    },
    onNudgePatchLastMessageRealismState: (tod, dc) {
      if (_messages.isNotEmpty) {
        final lastMsg = _messages.last;
        lastMsg.activeMetadata ??= {};
        final existingState = lastMsg.activeMetadata!['realism_state'];
        if (existingState is Map<String, dynamic>) {
          existingState['timeOfDay'] = tod;
          existingState['dayCount'] = dc;
          existingState['time_nudged'] = true;
        } else {
          lastMsg.activeMetadata!['realism_state'] = _captureRealismState();
          lastMsg.activeMetadata!['realism_state']['time_nudged'] = true;
        }
      }
    },
  );

  // ── Chaos Mode (extracted; late final here for injection safety, before _chaosInjection) ──
  late final _chaosModeService = ChaosModeService(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    onSetPendingRealismMetadata: (key, value) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata![key] = value;
    },
  );

  // ── NSFW cooldown & arousal (extracted to NsfwService) ─────────────────────
  // State (cooldown enabled/remaining/total, arousalLevel), tier calc, reset/seed/load/restore,
  // group per-speaker load/save scalars, applyClimax/decrement live in _nsfwService (plain class).
  // ChatService owns via late final + delegates. (Declared before needs for init safety because
  // needs closes over the getArousal/getNsfw/getCooldown/setArousal cbs.)
  // Reset helpers on service keep the multiple "keep reset blocks in sync" sites correct (now incl needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; no reset scalar) comments)
  // without god privates. 0 new private methods in god.
  // _runPostGenNeedsChecks thin (consolidated to needs_impact_evaluator); 3 group cbs only (onNotify/onSaveChat removed as dead; god owns save/notify for post-gen fidelity per plan). (cross-ref setActiveCharacter:1572 etc)
  late final _nsfwService = NsfwService(
    getGroupInt: _getGroupInt,
    getGroupValue: (charId, key) => _groupRealism[charId]?[key],
    setGroupValue: _setGroupRealismValue,
  );

  // ── Lorebook scanner (extracted to LorebookScanner) ────────────────────────
  // Keyword match (_matchKeyword with raw+concat fix), scan (per-char + worlds,
  // set isTriggered + remaining=sticky), decrement (post-AI pre-set only),
  // reset of non-const trigger state live in _lorebookScanner (plain class).
  // ChatService owns via late final + thin delegations at *all* call sites.
  // getActiveGroupLoreEntries + _buildLorebookContext (injection text) + preAi
  // snapshot stay in god (per plan; lorebook injection text / full context
  // building kept thin/stayed in god for step8).
  // 0 new god private _ methods.
  // 3 granular cbs (onNotify + getLoreCharacters for group/1:1 cards + resolveWorld)
  // to access live _groupCharacters/_activeCharacter and _worldRepository without
  // whole-parent or cycles (mirrors nsfw group scalars precedent; testable via
  // live closures in createTestLorebookScanner; aug only passive/qualified).
  // 1:1 vs group parity: scanner processes whatever chars cb provides (all group
  // members + their worlds for group; single for 1:1); depth per-entry.
  // Reset hygiene: resetLorebookTriggerState() called from every keep-sync site
  // (startNewChat 1:1+group/ext+non-ext, setActive*, _load empty/0-session, setActiveGroup defensive+post, etc);
  // (see CLAUDE.md keep-sync + incomplete zeroing + buffer removal complete; aug only qualified passive).
  late final _lorebookScanner = LorebookScanner(
    onNotify: notifyListeners,
    getLoreCharacters: () => _activeGroup != null
        ? _groupCharacters
        : (_activeCharacter != null
              ? [_activeCharacter!]
              : const <CharacterCard>[]),
    resolveWorld: (name) =>
        _worldRepository.worlds.where((w) => w.name == name).firstOrNull,
  );

  late final _needsSimulation = NeedsSimulation(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getTimeOfDay: () => _timeService.timeOfDay,
    getRealismEnabled: () => _realismEnabled,
    getArousalLevel: () => _nsfwService.arousalLevel,
    getNsfwCooldownEnabled: () => _nsfwService.nsfwCooldownEnabled,
    getCooldownTurnsRemaining: () => _nsfwService.cooldownTurnsRemaining,
    getObserverMode: () => _observerMode,
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getGroupNeeds: _getGroupNeeds,
    setGroupNeeds: _setGroupNeeds,
    getEnjoysLowHygiene: () => enjoysLowHygiene,
    getNeedsSimEnabled: () => _needsSimEnabled,
    setArousalLevel: (v) => _nsfwService.setArousalLevel(v),
    getCustomDecayRates: () {
      if (_activeGroup != null) return _groupDecayRates;
      final ext = _activeCharacter?.frontPorchExtensions;
      if (ext == null) return const <String, int>{};
      return {
        'hunger': ext.needsDecayHunger,
        'bladder': ext.needsDecayBladder,
        'energy': ext.needsDecayEnergy,
        'social': ext.needsDecaySocial,
        'fun': ext.needsDecayFun,
        'hygiene': ext.needsDecayHygiene,
        'comfort': ext.needsDecayComfort,
      };
    },
  );

  late final _relationshipService = RelationshipService(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getIsGroupActive: () => _activeGroup != null,
    getObserverMode: () => _observerMode,
    getGroupCharacterCount: () => _groupCharacters.length,
    getShouldTrackInterCharacterRelationships: () =>
        _shouldTrackInterCharacterRelationships,
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getCurrentGroupMemberIds: () =>
        _groupCharacters.map(_getCharacterIdFromCard).toSet(),
    getOtherGroupMemberIds: (selfId) => _groupCharacters
        .map(_getCharacterIdFromCard)
        .where((id) => id != selfId)
        .toList(),
    getOtherGroupMemberIdToLowerName: (selfId) {
      final m = <String, String>{};
      for (final other in _groupCharacters) {
        final oid = _getCharacterIdFromCard(other);
        if (oid == selfId) continue;
        m[oid] = other.name.toLowerCase();
      }
      return m;
    },
    getRecentExchangeLowerText: () {
      if (_messages.length < 2) return '';
      return _messages.reversed
          .take(2)
          .map((m) => m.displayText.toLowerCase())
          .join(' ');
    },
    getMessageCount: () => _messages.length,
    getIsGroupRealismActive: () => isGroupRealismActive,
    getGroupAffectionScore: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['affection'] as num?)?.toInt() ?? defaultValue,
    setGroupAffectionScore: (charId, v) =>
        _setGroupRealismValue(charId, 'affection', v),
    getGroupLongTermScore: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['longTermScore'] as num?)?.toInt() ??
        defaultValue,
    setGroupLongTermScore: (charId, v) =>
        _setGroupRealismValue(charId, 'longTermScore', v),
    getGroupTrustLevel: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['trust'] as num?)?.toInt() ?? defaultValue,
    setGroupTrustLevel: (charId, v) =>
        _setGroupRealismValue(charId, 'trust', v),
    getGroupFixation: (charId, {String defaultValue = ''}) =>
        (_groupRealism[charId]?['fixation'] as String?) ?? defaultValue,
    setGroupFixation: (charId, v) =>
        _setGroupRealismValue(charId, 'fixation', v),
    getGroupFixationLifespan: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['fixationLifespan'] as num?)?.toInt() ??
        defaultValue,
    setGroupFixationLifespan: (charId, v) =>
        _setGroupRealismValue(charId, 'fixationLifespan', v),
    getGroupRelationshipTier: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['relationshipTier'] as num?)?.toInt() ??
        defaultValue,
    setGroupRelationshipTier: (charId, v) =>
        _setGroupRealismValue(charId, 'relationshipTier', v),
    getGroupLongTermTier: (charId, {int defaultValue = 0}) =>
        (_groupRealism[charId]?['longTermTier'] as num?)?.toInt() ??
        defaultValue,
    setGroupLongTermTier: (charId, v) =>
        _setGroupRealismValue(charId, 'longTermTier', v),
    getGroupSpatialStance: (charId, {String defaultValue = ''}) =>
        (_groupRealism[charId]?['spatialStance'] as String?) ?? defaultValue,
    setGroupSpatialStance: (charId, v) =>
        _setGroupRealismValue(charId, 'spatialStance', v),
    getGroupInterCharacterRelationships: (charId) {
      final raw = _groupRealism[charId]?['relationships'];
      if (raw is Map) {
        return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
      }
      return const <String, int>{};
    },
    setGroupInterCharacterRelationships: (charId, rels) =>
        _setGroupRealismValue(charId, 'relationships', rels),
  );

  // ── Expression label selection / manual / avatar resolve / reclass / ONNX (extracted) ────
  // currentExpressionLabel (manual priority + LLM map + ONNX debounce/cache/stability),
  // resolveExpressionAvatar (random + lastId reroll), setManual, reclassifyEmotion,
  // init/set for classifier service, _reclassify/_classifyOnnx async, caches, Random,
  // lastAvatarId now owned by ExpressionService (plain class).
  // ChatService owns via late final + delegates. Prompt injection (label lists) + command
  // coordination kept in god (step 8). Reset/invalidate helpers on service keep the
  // multiple "keep reset blocks in sync" + regen sites correct without god privates (needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; thin/legacy in evaluator; no god reset scalar)" ). (cross-ref setActiveCharacter:1572 etc)
  late final _expressionService = ExpressionService(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getIsEvaluatingRealism: () => _isEvaluatingRealism,
    getStorageService: () => _storageService,
    getLlmServiceForReclass: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    getIsGenerating: () => _isGenerating,
    getCharacterEmotion: () => _characterEmotion,
    getMessages: () => _messages,
    getIsThinkingModelForReclass: () {
      // Preserve original expression reclass isThinking logic (ignores testLlmOverride for isLocal,
      // consistent with pre-extraction).
      final llmP = _llmProvider;
      if (llmP != null && llmP.isLocal) {
        return _storageService.backendSettings.koboldThinkingModel;
      }
      if (llmP != null) {
        return _storageService.backendSettings.reasoningEnabled;
      }
      return false;
    },
    getRealismEvalCancelled: () => _realismEvalCancelled,
    setRealismEvalCancelled: (v) => _realismEvalCancelled = v,
    setIsEvaluatingRealism: (v) => _isEvaluatingRealism = v,
    onHandleRealismEvalCancelledDuringOnnx: () async {
      _messages.add(
        ChatMessage(
          text: 'Realism evaluation interrupted, regenerate response to retry',
          sender: 'Interruption',
          isUser: false,
        ),
      );
      await _saveChat();
      _realismEvalCancelled = false;
      _isEvaluatingRealism = false;
      notifyListeners();
    },
  );

  // ── Prompt Injection Builders (step 8: all _get*Injection moved to prompt_injection/*) ──
  // 8 plain classes (author_note for objective, relationship for rel+inter+trust, emotion,
  // behavioral, time, nsfw, chaos for chance, needs).
  // Each wired with onNotify + granular cbs for 1:1 vs group dispatch (speaker, group chars/ints/needs,
  // realism flags, emotion state, hygiene, active char, objective state) + direct service deps for
  // their owned state (rel scores/tiers/fix/spatial, needs vector, nsfw cooldown/arousal, time scalars,
  // chaos pending, etc). Mirrors nsfw/relationship/lore cbs precedent.
  // God owns late finals + thin delegations at assembly call sites (relationship/emotion/time/trust/
  // cooldown/behavioral/needs/inter/chance/objective). 0 @Deprecated shims. 0 new god private _ methods.
  // Some coordination (objective list mgmt/assembly, lore _buildLorebookContext + getActiveGroupLoreEntries + preAi snapshot, chance _pendingChanceTimeEvent / _chanceTime* / completer / UI flags, _runPostGen checks) stayed thin in god per plan boundaries for step8 (qualified in headers/MD/gates + 8 builder headers + test + won'tfix).
  // (see CLAUDE.md for reset keep-sync + zeroing hygiene + authority simple).
  // 1:1 vs group + oneShot/normal dispatch preserved exactly (cbs + service state).
  // aug exercising only passive/qualified (no prompt-specific aug file edits; ... per step7 precedent).
  late final _authorNoteBuilder = AuthorNoteBuilder(
    getActiveObjectives: () => _activeObjectives,
    getPrimaryObjective: () => primaryObjective,
    tasksForObjective: (o) => tasksForObjective(o),
    getSecondaryObjectives: () => secondaryObjectives,
  );

  late final _relationshipInjection = RelationshipInjection(
    relationshipService: _relationshipService,
    getRealismEnabled: () => _realismEnabled,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getActiveCharacter: () => _activeCharacter,
    getShortTermTierName: () => _relationshipService.shortTermTierName,
    getLongTermTierName: () => _relationshipService.longTermTierName,
    getMoodLabel: () => moodLabel,
    getShouldTrackInterCharacterRelationships: () =>
        _shouldTrackInterCharacterRelationships,
    getGroupInt: _getGroupInt,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getInterCharacterRelationships:
        _relationshipService.getInterCharacterRelationships,
  );

  late final _emotionInjection = EmotionInjection(
    getRealismEnabled: () => _realismEnabled,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getActiveCharacter: () => _activeCharacter,
    getCharacterEmotion: () => _characterEmotion,
    getEmotionIntensity: () => _emotionIntensity,
    getCharacterIdFromCard: _getCharacterIdFromCard,
  );

  late final _behavioralInjection = BehavioralInjection(
    relationshipService: _relationshipService,
    getRealismEnabled: () => _realismEnabled,
    getActiveCharacter: () => _activeCharacter,
  );

  late final _timeInjection = TimeInjection(timeService: _timeService);

  late final _nsfwInjection = NsfwInjection(
    nsfwService: _nsfwService,
    needsSimulation: _needsSimulation,
    relationshipService: _relationshipService,
    getRealismEnabled: () => _realismEnabled,
    getActiveCharacter: () => _activeCharacter,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getCharacterIdFromCard: _getCharacterIdFromCard,
  );

  late final _chaosInjection = ChaosInjection(
    chaosModeService: _chaosModeService,
    getActiveCharacter: () => _activeCharacter,
  );

  late final _needsInjection = NeedsInjection(
    needsSimulation: _needsSimulation,
    nsfwService: _nsfwService,
    getNeedsSimEnabled: () => _needsSimEnabled,
    getRealismEnabled: () => _realismEnabled,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getActiveCharacter: () => _activeCharacter,
    getEnjoysLowHygiene: () => enjoysLowHygiene,
    getGroupNeeds: _getGroupNeeds,
    getCharacterIdFromCard: _getCharacterIdFromCard,
  );

  // ── LLM Eval Engine (step 9: _fireLLMEval + strip + extract + needs impact cb) ──
  // Plain class (not ChangeNotifier). Owns the central eval firing (streaming/retry/cancel, 4000/0.1/no-reasoning),
  // central strip (completed+unclosed), JSON extractors, evaluateNeedsImpactCall (for needs_impact_evaluator).
  // The 5 realism eval prompt builders + calls (rel/emotion/phys/narr w/ proposed_objective, oneShot) moved to
  // sibling leaf realism_evals.dart (step 10); this engine provides fire/strip/extract cbs to it (granular).
  // objective proposal handling + generateObjectiveTasks + _checkTaskCompletionInBackground moved to
  // sibling leaf objective_proposal.dart (step 11); this engine provides strip cb to it (for 2000 paths).
  // Wired with granular cbs for 1:1 vs group (via impersonation for speaker), test overrides,
  // pending/emotion state, capture, + service deps (rel) .
  // (onNotify/onSaveChat removed in step 10 fix round 1 + step11: oneShot populates pending snapshot;
  // god owns the post-eval _saveChat/notify in pre-turn + baseline paths to avoid double + races;
  // on* dead post step11 objective move, cleaned).
  // 0 @Deprecated shims. 0 new god private _ methods beyond the required thin delegates (_fireLLMEval, _stripThinkBlocks, _extractJson*, evaluateNeedsImpactCall; the 5 _evaluate*Call thins now point to realism_evals; generate/check thins now to objective_proposal; the void _ count grep stayed 15; +1 late final only; thins/calls/late final only per plan). (cross-ref setActiveCharacter:1572 etc)
  // Stateless/prompt-only: no reset calls needed. Reset hygiene comments list full set + llm_eval_engine (stateless or prompt-only;
  // no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + summary_service (stateless or prompt-only; no reset calls needed) + cross-refs (e.g. setActiveCharacter:1572). Both startNew branches explicit.
  // 1:1 vs group + oneShot vs normal dispatch/parity preserved exactly (cbs + impersonation temp re-load; qualified).
  // aug exercising only passive/qualified (no llm-eval-specific aug file edits; resets/loads/greetings/post hit by pre-existing
  // startNew/setActive/_loadLast/group in key suites; full eval/JSON/strip + needs impact only in dedicated + manual;
  // objective proposal/gen/check exercised via god thins generate/check ; qualified notes only in dedicated header + god + MD per precedent).
  late final _llmEvalEngine = LlmEvalEngine(
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getIsObserverMode: () => _observerMode,
    getUserName: () => _userPersonaService.persona.name,
    getRealismEnabled: () => _realismEnabled,
    getMessages: () => _messages,
    getLlmService: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    getIsLocal: () => testLlmServiceOverride != null
        ? testIsLocalOverride
        : (_llmProvider?.isLocal ?? false),
    getKoboldService: () => _llmProvider?.koboldService,
    reconnectIfAlive: () async {
      final k = _llmProvider?.koboldService;
      if (k != null) await k.reconnectIfAlive();
    },
    ensureServerIdle: () async {
      final k = _llmProvider?.koboldService;
      if (k != null) await k.ensureServerIdle();
    },
    getIsCancellingRealismEval: () => _isCancellingRealismEval,
    getRealismEvalCancelled: () => _realismEvalCancelled,
    getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
    setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
    captureRealismState: _captureRealismState,
    getCharacterEmotion: () => _characterEmotion,
    setCharacterEmotion: (v) => _characterEmotion = v,
    getEmotionIntensity: () => _emotionIntensity,
    setEmotionIntensity: (v) => _emotionIntensity = v,
    relationshipService: _relationshipService,
  );

  // ── Realism Evals (step 10: the 5 realism evaluation calls — relationship, emotional, physical, narrative, one-shot) ──
  // Plain leaf sibling to LlmEvalEngine. Owns the 5 eval prompt builders + call orchestration + parse for realism results
  // (bond/trust/emotion/arousal/fixation/spatial stance/time + pending for chips/reasons) + side effects (apply deltas on
  // rel/nsfw, set emotion scalars, updateFixation, setObjective thin for autonomous, snapshot in oneShot).
  // Depends on llm_eval_engine for fire/strip/extract cbs (wired via god thins for centralization).
  // Some coordination (setObjective thin for proposal, physical posture delegate to timeService) stayed thin/coordinated
  // per precedent (qualify).
  // ChatService owns via late final (after engine) + thins/delegates at *every* prior call site for the 5 _evaluate*Call
  // (full excision of moved code from engine + prior thin bodies).
  // 0 @Deprecated shims. 0 new god private _ methods (thins stay in god as the public surface; void _ count grep stays 15
  // confirmed after every edit + final; +1 late final + thins/calls + reset comment syncs only per plan).
  // Stateless/prompt-only: no reset calls needed. See expanded "keep reset blocks in sync" comments at *all* ~15+ sites
  // (see CLAUDE.md full list + incomplete zeroing hygiene; buffer removal complete)
  // zeroing of secondary config on group/0-session/new-chat now complete"; both startNew branches explicit; cross-refs
  // e.g. setActiveCharacter:1572).
  // 1:1 vs group + oneShot vs normal + Realism/Needs/Objectives parity 1:1 equivalent deltas/behavior at all times
  // (cbs + god's impersonation dance + load/saveScalarsIntoGroupRealism before speaker evals; qualified; exercised in
  // dedicated + key suites + manual).
  // aug exercising only passive/qualified (no realism-evals-specific aug file edits; full in dedicated
  // realism_evals_test + manual; exercised via god thins _evaluate*Call ; qualified notes only in dedicated header + god
  // + MD per precedent).
  // Realism Verification (Director/Verifier) — new optional leaf (plan 2026-04).
  // late final after _llmEvalEngine (for dep on fire/strip/extract + state cbs; before evals/impact so they can receive the cb in their ctors).
  // Granular cbs only (live closures for group impersonation + test). Receives *full* latent bundle from callers (the two leaves assemble prompt/pre/char/scene/raw/kind/strict/max at their fire sites).
  // 0 new god void _ (thins + this late final + god-owned _isVerifying* + getters only).
  late final _realismVerifier = RealismVerification(
    fireLLMEval: (p, {onChunk}) => _fireLLMEval(p, onChunk: onChunk),
    stripThinkBlocks: _stripThinkBlocks,
    extractJsonInt: _extractJsonInt,
    extractJsonBool: _extractJsonBool,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getIsObserverMode: () => _observerMode,
    getUserName: () => _userPersonaService.persona.name,
    getMessages: () => _messages,
    getRealismVerificationEnabled: () =>
        (_activeCharacter?.frontPorchExtensions?.realismVerificationEnabled ??
            false) &&
        _realismEnabled &&
        (_activeGroup == null || !_observerMode),
    getVerificationMaxReprocesses: () =>
        _activeCharacter
            ?.frontPorchExtensions
            ?.realismVerificationMaxReprocesses ??
        1,
    getVerificationStrictness: () =>
        _activeCharacter?.frontPorchExtensions?.realismVerificationStrictness ??
        3,
    captureRealismState: _captureRealismState,
    getPreTurnNeedsVector: () => _needsSimulation.vector,
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    onVerificationPhase: (verifying, {pass = 0, max = 1}) {
      _isVerifyingRealism = verifying;
      _verificationPass = pass;
      _verificationMaxPasses = max;
      notifyListeners();
    },
    isCancelling: () => _isCancellingRealismEval,
  );

  // ── Needs Impact Evaluator (post-buffer: straight model deltas + optional Director) ──
  // See CLAUDE.md (buffer removal complete; authority branch via cb; 1:1/group parity).
  late final _needsImpactEvaluator = NeedsImpactEvaluator(
    evaluateNeedsImpactCall: _llmEvalEngine.evaluateNeedsImpactCall,
    verifyRealismOutput: _realismVerifier.verify,
    fireLLMEval: (p, {onChunk}) => _fireLLMEval(p, onChunk: onChunk),
    getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
    setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getIsObserverMode: () => _observerMode,
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getGroupNeeds: _getGroupNeeds,
    setGroupNeeds: _setGroupNeeds,
    getGroupCharacters: () => _groupCharacters,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getMessages: () => _messages,
    needsSimulation: _needsSimulation,
    getNeedsSimEnabled: () => _needsSimEnabled,
    getRealismEnabled: () => _realismEnabled,
    getNeedsModelAuthorityEnabled: () =>
        (_activeCharacter
            ?.frontPorchExtensions
            ?.realismNeedsDirectorAuthority ??
        false),
    getNeedsSimStrength: () =>
        (_activeCharacter?.frontPorchExtensions?.needsSimStrength ?? 1),
    onClimax: (turns) {
      final preClimaxArousal = _nsfwService.arousalLevel;
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        final msg = _messages.last;
        final meta = Map<String, dynamic>.from(msg.activeMetadata ?? {});
        meta['climax_triggered'] = true;
        meta['pre_climax_arousal'] = preClimaxArousal;
        msg.swipeMetadata[msg.swipeIndex] = meta;
      }
      _nsfwService.applyClimaxEffects(turns: turns);
    },
  );

  late final _realismEvals = RealismEvals(
    fireLLMEval: (p, {onChunk}) => _fireLLMEval(p, onChunk: onChunk),
    stripThinkBlocks: _stripThinkBlocks,
    extractJsonInt: _extractJsonInt,
    extractJsonBool: _extractJsonBool,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getIsObserverMode: () => _observerMode,
    getUserName: () => _userPersonaService.persona.name,
    getRealismEnabled: () => _realismEnabled,
    getMessages: () => _messages,
    getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
    setPendingRealismMetadata: (v) => _pendingRealismMetadata = v,
    captureRealismState: _captureRealismState,
    getCharacterEmotion: () => _characterEmotion,
    setCharacterEmotion: (v) => _characterEmotion = v,
    getEmotionIntensity: () => _emotionIntensity,
    setEmotionIntensity: (v) => _emotionIntensity = v,
    relationshipService: _relationshipService,
    nsfwService: _nsfwService,
    timeService: _timeService,
    getExpressionEnabled: () =>
        _storageService.expressionSettings.expressionEnabled,
    getPrimaryObjective: () => primaryObjective,
    getActiveObjectives: () => _activeObjectives,
    setObjective: (text, {isPrimary = false, autoGenerateTasks = false}) =>
        setObjective(
          text,
          isPrimary: isPrimary,
          autoGenerateTasks: autoGenerateTasks,
        ),
    verifyRealismOutput: _realismVerifier.verify,
  );

  // ── Objective Proposal (step 11: proposal path support + generateObjectiveTasks + _checkTaskCompletionInBackground) ──
  // Plain leaf sibling to LlmEvalEngine (and realism_evals). Owns generateObjectiveTasks
  // (2000 + central strip via cb for thinking models) + checkTaskCompletionInBackground
  // (2000 + strip; task vs taskless) + internal prompt/parse.
  // The autonomous "none" vs value + dedup + autoGenerateTasks:true only for autonomous
  // lives in realism_evals (narr/oneShot); correct target under group impersonation via
  // god dance + live cbs; objective mgmt (setObjective, load/save/deact, tasksFor,
  // isChecking, _activeObjectives, markTaskCompleted) stay thin/coordinated in god per plan
  // (qualify; "thin delegation here; full objective proposal in step 11").
  // ChatService owns via late final (after _realismEvals) + thins/delegates at *every*
  // prior call site for generate + _check (full excision from engine + old thin bodies).
  // 0 @Deprecated shims. 0 new god private _ methods (thins as public surface; void _
  // count grep stays 15 confirmed after every edit + final; +1 late final + thins/calls
  // + reset comment syncs only per plan).
  // Stateless/prompt-only: no reset calls needed. See "keep reset blocks in sync" + "incomplete zeroing now complete" + authority (simple model+Director) + full leaf list in CLAUDE.md (both startNew; cross-refs e.g. setActiveCharacter:1572).
  // 1:1 vs group + oneShot/normal parity for proposed "none"/value + dedup + auto only
  // autonomous + correct target (even under impersonation; decision/attach via dance, gen prompt read best-effort/timing-dep as qualified in leaf + test + impersonation finally); task vs taskless (mark cb mutation in god for task auto); 2000+central
  // strip; dispatch preserved via cbs + god impersonation. (Fix round 2 updates: timing qualify, zeroing of _isChecking + messagesSince now explicit at all sites + "now complete", mark cb, getPrimary del as dead, test bodies 11 post del, lints 0, claims updated only post re-gates/re-reads).
  // aug exercising only passive/qualified (no objective-proposal-specific aug file edits;
  // full in dedicated objective_proposal_test + manual; exercised via god thins
  // generate/check ; qualified notes only in dedicated header + god + MD per precedent).
  late final _objectiveProposal = ObjectiveProposal(
    stripThinkBlocks: _stripThinkBlocks,
    getLlmService: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getIsObserverMode: () => _observerMode,
    getUserName: () => _userPersonaService.persona.name,
    getRealismEnabled: () => _realismEnabled,
    getMessages: () => _messages,
    getActiveObjectives: () => _activeObjectives,
    tasksForObjective: tasksForObjective,
    loadActiveObjectives: _loadActiveObjectives,
    saveObjectiveTasks: (id, json) async {
      await _db.updateObjective(
        ObjectivesCompanion(id: drift.Value(id), tasks: drift.Value(json)),
      );
    },
    deactivateObjective: (id) async {
      await _db.updateObjective(
        ObjectivesCompanion(
          id: drift.Value(id),
          active: const drift.Value(false),
        ),
      );
    },
    markTaskCompleted: markTaskCompleted,
    getIsCheckingCompletion: () => _isCheckingCompletion,
    setIsCheckingCompletion: (v) => _isCheckingCompletion = v,
    onNotify: notifyListeners,
  );

  // ── Chat Summary (step 12: _generateSummaryInBackground + _maybeUpdateSummary + force + prompt/RAG/strip/update) ──
  // Plain leaf sibling to LlmEvalEngine / realism_evals / objective_proposal.
  // Owns the full generate (prompt template macros {{words}}/{{user}}/{{char}}, history
  // condensation skipping director, previousSummaryBlock, RAG grounding via getMemorySourceIds +
  // getAllContentForCharacters, genParams max=words*3 / temp 0.3 / no-reasoning / stops, stream
  // accumulate, strip think completed+unclosed + numbered analysis preamble skip + trailing
  // sentence trim, result update via cbs + save/notify).
  // Cadence (user msg count since lastIndex >= storage.interval), pause, force, enabled,
  // flag _isSummaryGenerating, scalars _summary/_lastIndex/_paused, save/load in session,
  // reset zeros stay thin/coordinated in god per plan ("thin delegation here; full summary
  // in step 12"). God thins at every prior call site + post-gen call site (full excision
  // of old _generate body).
  // 0 @Deprecated. 0 new god private _ methods (thins as public surface; void _ count
  // grep stays 15 after every edit + final; +1 late final + thins/calls + reset comment
  // syncs only per plan).
  // Stateless/prompt-only: no reset calls needed on leaf. See expanded "keep reset blocks
  // in sync" at *all* ~15+ sites (full prior+current list + summary_service (stateless or
  // prompt-only; no reset calls needed) + "incomplete zeroing of secondary config on
  // group/0-session/new-chat now complete"; both startNew branches explicit; cross-refs
  // e.g. setActiveCharacter:1572).
  // 1:1 vs group parity for summary text/lastIndex/paused/generating/force/pause/cadence
  // (dispatch preserved via cbs; summary per-chat, context names/RAG correct at trigger).
  // aug exercising only passive/qualified (no summary-specific aug file edits; full in
  // dedicated summary_service_test + manual; exercised via god thins _maybeUpdateSummary/
  // force/generate ; qualified notes only in dedicated header + god + MD per precedent).
  // Anti-accumulation: explicit dead audit (no new _Summary/*Summary privates in god);
  // deletion of moved bodies as part of task.
  // Barrel not added (internal to ChatService; per "unless 3+ locations").
  late final _summaryService = SummaryService(
    getLlmService: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    getSummaryEnabled: () => _storageService.memorySettings.summaryEnabled,
    getSummaryInterval: () => _storageService.memorySettings.summaryInterval,
    getSummaryPrompt: () => _storageService.memorySettings.summaryPrompt,
    getSummaryMaxWords: () => _storageService.memorySettings.summaryMaxWords,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getUserName: () => _userPersonaService.persona.name,
    getMessages: () => _messages,
    getCurrentSummary: () => _summary,
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getIsSummaryGenerating: () => _isSummaryGenerating,
    setIsSummaryGenerating: (v) => _isSummaryGenerating = v,
    updateSummary: (t) => _summary = t,
    updateSummaryLastIndex: (i) => _summaryLastIndex = i,
    isMemoryOperational: () =>
        _memoryService != null && _memoryService!.isOperational,
    getMemorySourceIds: _getMemorySourceIds,
    getAllContentForCharacters: (ids) =>
        _memoryService!.getAllContentForCharacters(ids),
  );

  // ── Fact Extraction (step 13: _extractFactsInBackground full + _consolidate + _isValidFact + quality gate + RP-aware prompt + consolidate) ──
  // Plain leaf sibling to LlmEvalEngine / realism_evals / objective_proposal / summary_service.
  // Owns the full extract (early guard + set flag via cb, recent user msgs filter skip __director__ + last 10,
  // existingFacts block + userName, displayText, charNames list from active+group for exclusion + charNamesStr,
  // long strict RP-aware extractionPrompt with CRITICAL RULES (only universal timeless context-free real-person facts,
  // ignore all RP/* / in-char / fictional / relationship / character names / scene-specific), GOOD/BAD examples,
  // isThinkingModel (local + koboldThinking/reasoningEnabled), GenerationParams (1024/0.2/1.15, stop ] or ]\n,
  // banEos/trim for local thinking), stream generate with early break if after strip ends with ']', accumulate,
  // post-stream strip think (use central), trim, debug raw, ```json codeblock extraction, RegExp \[.*\] dotAll parse
  // + jsonDecode to List<String>, if empty or parse fail debug+return, cleanFacts=where(_isValidFact), log rejected,
  // if empty after gate return, log accepted, await addLearnedFacts(clean + embed if avail), currentCount > max →
  // await _consolidate, debug saved) + consolidate (facts copy, <=max return, consolidationPrompt (merge related dense
  // preserving ALL specific details, ex cat+name+color, remove redundant, drop vague, target ~max or fewer, ONLY JSON array),
  // raw = await fireLLMEval, null→fallback truncate+update+return, text=strip, codeblock strip, arrayMatch, no match fallback,
  // try { consolidated=jsonDecode, cleaned=where _isValid, debug before→after, update with cleaned } catch fallback truncate).
  // Cadence/flag/counter/periodic orchestration / enabled / sequence / call sites / load/save of transients stay thin
  // in god per plan ("thin delegation here; full fact extraction in step 13").
  // God late final (after _summaryService) + thins/delegates at *every* prior call site (the one in
  // _runPeriodicEvalsInSequence and the guard/flag use) with *full excision* of the moved bodies from god.
  // 0 @Deprecated shims. 0 new god private _ methods (thins as the public surface; live `grep -c '^\s*void _[a-zA-Z]' lib/services/chat_service.dart` *must stay exactly 15* after *every* edit + final; +1 late final + thins/calls + reset comment syncs only).
  // Stateless/prompt-only (no owned reset/seed/load state for processing — god owns the scalars/flags/cadence; no reset calls needed on leaf).
  // God reset "keep blocks in sync" comments expanded at *all* ~15+ documented sites (full prior+current list + fact_extraction (stateless or prompt-only; no reset calls needed) + evolution_service (stateless or prompt-only; no reset calls needed) + realism_verification (stateless or prompt-only; no reset calls needed) + "incomplete zeroing... now complete (see CLAUDE.md)"; both startNew branches explicit; cross-refs e.g. setActiveCharacter:1572).
  // 1:1 vs group parity for fact extraction (rejection of current+group char names must work identically; dispatch preserved via cbs; facts are user-global but context for extraction/rejection is chat-specific).
  // aug/integration tests receive *only* qualified passive notes in headers/comments (exact precedent phrasing from step 12: "aug exercising only passive/qualified (no fact-extraction-specific aug file edits; full in dedicated + manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_extractFactsInBackground ; qualified notes only in dedicated header + god + MD per precedent)"); no leaf-specific logic edits.
  // Anti-accumulation/dead-code audit (explicit greps of affected methods in god; no new _Fact/*Fact/ExtractFact privates in god; deletion of moved + any dead/vestigial as part of task).
  // Barrel not added (internal to ChatService only; per "unless 3+ locations").
  late final _factExtraction = FactExtraction(
    getLlmService: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    fireLLMEval: (p) => _fireLLMEval(p),
    stripThinkBlocks: _stripThinkBlocks,
    getIsLocal: () => testLlmServiceOverride != null
        ? testIsLocalOverride
        : (_llmProvider?.isLocal ?? false),
    getKoboldThinkingModel: () =>
        _storageService.backendSettings.koboldThinkingModel,
    getReasoningEnabled: () => _storageService.backendSettings.reasoningEnabled,
    getUserName: () => _userPersonaService.persona.name,
    getLearnedFacts: () => _userPersonaService.persona.learnedFacts,
    addLearnedFacts: (facts, {embedService}) =>
        _userPersonaService.addLearnedFacts(facts, embedService: embedService),
    updateLearnedFacts: (facts) async {
      final p = _userPersonaService.persona;
      await _userPersonaService.updatePersona(p.copyWith(learnedFacts: facts));
    },
    getActiveCharacter: () => _activeCharacter,
    getGroupCharacters: () => _groupCharacters,
    getMessages: () => _messages,
    getIsExtractingFacts: () => _isExtractingFacts,
    setIsExtractingFacts: (v) => _isExtractingFacts = v,
    isMemoryOperational: () =>
        _memoryService != null && _memoryService!.isOperational,
    getEmbeddingService: () => _memoryService?.embeddingService,
  );

  // Thin delegation (full _extractFactsInBackground + consolidate + quality gate + prompt/LLM/stream/JSON/_isValidFact
  // in fact_extraction step 13; cadence/flag/counter/periodic orchestration / enabled / sequence / call sites stay thin
  // in god per plan; "thin delegation here; full fact extraction in step 13").
  Future<void> _extractFactsInBackground() =>
      _factExtraction.extractFactsInBackground();

  // ── Character Evolution (step 14) wiring ──
  // Plain leaf sibling to fact_extraction / summary_service / llm_eval_engine etc.
  // owns the full evolution trigger/extract/reset + effective personality/scenario layering
  // + group per-char counts + LLM for traits + status/error.
  // Periodic coordination / enabled / trigger call sites / load/save of evolved scalars/maps
  // stay thin in god ("thin delegation here; full character evolution in step 14").
  // God late final (after _factExtraction) + thins/delegates at *every* prior call site for
  // trigger/manual/getEffective* (full excision of moved bodies), 0 @Deprecated shims,
  // 0 new god private _ methods (thins as the public surface; live `grep -c '^\s*void _[a-zA-Z]'
  // lib/services/chat_service.dart` *must stay exactly 15* after *every* edit + final;
  // +1 late final + thins/calls + reset comment syncs only).
  // Stateless/prompt-only (no owned reset/seed/load state for evolution processing —
  // god owns the maps/scalars/flags/counts; no reset calls needed on leaf).
  // God reset "keep blocks in sync" comments expanded at *all* ~15+ documented sites
  // (see CLAUDE.md full list + incomplete zeroing hygiene; buffer removal complete)
  // + "incomplete zeroing... now complete (see CLAUDE.md)"
  // + *both* startNewChat branches explicit + cross-refs e.g. setActiveCharacter:1572).
  // Explicit _isEvolvingCharacter=false + _evolutionStatus='' + _evolutionError='' (modeled on _isExtractingFacts) added at 10+ sites + decl + startNew both + common in fix round to make "now complete" hold in *code* (not just comments); maps/counts were already present.
  // 1:1 vs group parity for evolution (per-char counts, effective personality/scenario layering,
  // trigger behavior must be identical whether 1:1 or group per-speaker; dispatch preserved
  // via cbs + god's impersonation dance where needed for target).
  // aug/integration tests receive *only* qualified passive notes in headers/comments (exact
  // precedent phrasing from step 13: "aug exercising only passive/qualified (no evolution-specific
  // aug file edits; full in dedicated + manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_triggerCharacterEvolution ;
  // qualified notes only in dedicated header + god + MD per precedent)"); no leaf-specific logic edits.
  // Anti-accumulation/dead-code audit (explicit greps of affected methods in god; no new
  // _Evol/*Evol/Evolution privates in god; deletion of moved + any dead/vestigial as part of task).
  // Barrel not added (internal to ChatService only; per "unless 3+ locations").
  late final _evolutionService = EvolutionService(
    getLlmService: () =>
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService,
    stripThinkBlocks: _stripThinkBlocks,
    getUserName: () => _userPersonaService.persona.name,
    getActiveCharacter: () => _activeCharacter,
    getGroupCharacters: () => _groupCharacters,
    getMessages: () => _messages,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getSummary: () => _summary,
    getIsNewChat: () => _isNewChat,
    fetchRecentMemoryChunksForEvolution: () async {
      if (_memoryService == null ||
          !_memoryService!.isOperational ||
          _isNewChat) {
        return <String>[];
      }
      try {
        final sourceIds = await _getMemorySourceIds();
        final chunks = await _memoryService!.getAllContentForCharacters(
          sourceIds,
        );
        if (chunks.isNotEmpty) {
          final recent = chunks.length > 10
              ? chunks.sublist(chunks.length - 10)
              : chunks;
          return recent;
        }
      } catch (e) {
        debugPrint('[Evolution] RAG retrieval failed (non-fatal via cb): $e');
      }
      return <String>[];
    },
    getCharacterEvolutionEnabled: () =>
        _storageService.memorySettings.characterEvolutionEnabled,
    getEvolvedPersonality: (charId) => _evolvedPersonalities[charId],
    setEvolvedPersonality: (charId, v) => _evolvedPersonalities[charId] = v,
    getEvolvedScenario: (charId) => _evolvedScenarios[charId],
    setEvolvedScenario: (charId, v) => _evolvedScenarios[charId] = v,
    getEvolutionCountFor: (charId) => _groupEvolutionCounts[charId] ?? 0,
    setEvolutionCountFor: (charId, v) => _groupEvolutionCounts[charId] = v,
    // Note (D qualify per re-review): count persistence for group is mem-only (_groupEvolutionCounts snapshot) per current thin god load/save (1:1 has dedicated DB column + mirror in persist). Effective layering / trigger target parity with 1:1 is preserved exactly (via cbs + leaf). Group count UI (cards/sidebar) uses the mem snapshot. This is pre-existing (public surface / load/save of evolved maps/counts stayed thin/coordinated in god per step 14 plan "public surface stay thin in god"; not regressed by extraction).
    getIsEvolvingCharacter: () => _isEvolvingCharacter,
    setIsEvolvingCharacter: (v) => _isEvolvingCharacter = v,
    setEvolutionStatus: (s) {
      _evolutionStatus = s;
      notifyListeners();
    },
    setEvolutionError: (e) {
      _evolutionError = e;
      notifyListeners();
    },
    persistEvolvedForCharacter: (charId, pers, scen, count) async {
      if (_currentSessionId != null) {
        if (_activeGroup != null) {
          final session = await _db.getSessionById(_currentSessionId!);
          if (session != null) {
            final personalities = _tryParseJsonMap(
              session.groupEvolvedPersonalities,
            );
            final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
            personalities[charId] = pers;
            scenarios[charId] = scen;
            await _db.patchSession(
              SessionsCompanion(
                id: drift.Value(_currentSessionId!),
                groupEvolvedPersonalities: drift.Value(
                  jsonEncode(personalities),
                ),
                groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
              ),
            );
          }
        } else {
          await _db.patchSession(
            SessionsCompanion(
              id: drift.Value(_currentSessionId!),
              evolvedPersonality: drift.Value(pers),
              evolvedScenario: drift.Value(scen),
              evolutionCount: drift.Value(count),
            ),
          );
        }
      }
      _evolvedPersonalities[charId] = pers;
      _evolvedScenarios[charId] = scen;
      _groupEvolutionCounts[charId] = count;
      if (_activeCharacter != null &&
          _getCharacterIdFromCard(_activeCharacter!) == charId) {
        _characterEvolutionCount = count;
      }
      notifyListeners();
    },
  );

  // Thin delegation (full _trigger/_extract + effective layering + group per-char
  // + LLM/prompt/parse/persist in evolution_service step 14; cadence/flag/periodic
  // orchestration / enabled / sequence / call sites / load/save of evolved maps
  // stay thin in god per plan; "thin delegation here; full character evolution in step 14").
  void _triggerCharacterEvolution() =>
      _evolutionService.triggerCharacterEvolution();
  Future<bool> triggerEvolutionNow({CharacterCard? target}) =>
      _evolutionService.triggerEvolutionNow(target: target);

  // Effective getters now thin to leaf (layering owned in step 14 sibling).
  String _getEffectivePersonality(CharacterCard card) =>
      _evolutionService.getEffectivePersonality(card);
  String _getEffectiveScenario(CharacterCard card) =>
      _evolutionService.getEffectiveScenario(card);

  // Step 15 (refactor remaining `ChatService`): complete. God is now thin
  // coordinator/orchestrator + minimal god-owned state that per-plan stayed
  // (_groupRealism + _loadGroup*IntoScalars / _saveScalarsIntoGroupRealism /
  // _setGroup* / _loadGroupRealismStateFromSession / _sync... / _restore... ;
  // core sendMessage pre/post + _generateResponse (pick/eval dance/impersonation/
  // build* stayed / post-gen finalization) ; _buildChatHistoryWithBudget ;
  // _loadLastSession / _saveChat / _doSaveChat ; _pickNextGroupCharacter ;
  // _evaluateRealismForUpcomingGroupSpeaker ; _waitForTtsThenContinue + drain
  // buffer / _flush / _startDrainTimer ; _applyMoodDecay ; _maybeEmbedMessages ;
  // _runPostGenNeedsChecks thin + periodic thins; all reset keep-sync + "now complete" (see CLAUDE.md); 0 new god priv _ (count=15); thins + coord only. Buffer removal + simple authority complete.
  // (3 vestigial phrases cleaned: 2 briefing + 1 per-thin at _getNsfwCooldownInjection:7742) + thin consistency as part of
  // task (no heroic new splits; smallest change; no bloat/parallel paths).
  // 1:1 vs group parity preserved for all surfaces (dispatch via cbs + god
  // impersonation dance). aug tests: only qualified passive (no step-15 edits).
  // See docs/refactor-god-file-modularization.md Step 15 + CLAUDE Path Map.
  Completer<void>?
  _chanceTimeCompleter; // pauses sendMessage while wheel is active (UI coordination, stays in god)

  // ── Trust Repair ──
  // Armed on each severe trust drop (≥ -20 delta). Consumed on the very
  // next user message, then resets so future drops each get one shot.
  // Backing state + arming logic moved to RelationshipService.applyTrustDelta.
  // (No local field remains; @Deprecated shim on getter only.)

  // ── Context / Prompt Budget ──
  Map<String, int> _lastPromptBudget = {};
  String _lastAssembledPrompt = '';

  // ── Session Metadata ──
  String? _sessionName;
  String? _sessionDescription;

  // ── Per-session generation overrides ──
  ChatGenerationSettings _sessionGenSettings = ChatGenerationSettings();

  // ── Chat Branching ──
  String? _parentSessionId;
  int? _forkIndex;

  /// Default system prompt for group chats, designed to prevent characters
  /// from speaking for each other and maintain turn discipline.
  static const String defaultGroupSystemPrompt =
      'You are roleplaying in a multi-character group conversation. '
      'CRITICAL RULES:\n'
      '1. You MUST only write dialogue and actions for the character whose turn it is (indicated after <START>). '
      'NEVER write dialogue, thoughts, or actions for other characters or {{user}}.\n'
      '2. Stay fully in character \u2014 use the speaking character\'s unique voice, mannerisms, personality, and speech patterns.\n'
      '3. Keep your response focused on ONE character\'s contribution. Do not narrate what other characters do or say.\n'
      '4. React naturally to what other characters and {{user}} have said. Reference their words, but do not put words in their mouths.\n'
      '5. Write in the style of collaborative roleplay: use *asterisks* for actions/narration and regular text for dialogue.\n'
      '6. Keep responses concise and punchy \u2014 leave room for the next character to respond.\n'
      '7. Never break character or reference the fact that you are an AI.';

  /// System prompt for Observer Mode — characters interact with each other, user is not present.
  static const String observerModeSystemPrompt =
      'You are roleplaying in a multi-character group conversation. '
      'The user is NOT a participant in this story — they are an invisible observer/director. '
      'CRITICAL RULES:\n'
      '1. You MUST only write dialogue and actions for the character whose turn it is. '
      'NEVER write for other characters.\n'
      '2. Characters should interact naturally WITH EACH OTHER — address other characters by name, '
      'respond to what they said, react to their actions. Build on the conversation organically.\n'
      '3. Stay fully in character — use the speaking character\'s unique voice and personality.\n'
      '4. If a [Director] note appears, follow its guidance to steer the scene (introduce new topics, '
      'create conflict, have a character enter/leave, etc.) but do NOT acknowledge the director directly.\n'
      '5. Write in collaborative roleplay style: *asterisks* for actions, regular text for dialogue.\n'
      '6. Keep responses concise — leave room for the next character to respond.\n'
      '7. Never break character or reference being an AI.\n'
      '8. Characters may naturally address each other, start side conversations, argue, agree, '
      'tell stories, ask questions, or react emotionally — make the conversation feel alive and dynamic.';

  /// Default system prompt for local KoboldCPP backends (smaller models).
  /// Kept concise so it doesn't eat too much of the limited context window.
  static const String defaultKoboldSystemPrompt =
      'Write {{char}}\'s next reply in this roleplay with {{user}}. '
      'Stay in character as {{char}} at all times. '
      'Use *asterisks* for actions and narration, regular text for dialogue. '
      'Be creative, descriptive, and drive the scene forward. '
      'Never write actions or dialogue for {{user}}. '
      'Never break character or mention being an AI.';

  /// Default system prompt for remote API backends (large cloud models).
  /// Highly detailed to leverage the model's full capabilities.
  static const String defaultApiSystemPrompt =
      'You are an expert collaborative fiction writer and immersive roleplay partner. '
      'You write as {{char}} in an ongoing interactive story with {{user}}.\n\n'
      'CORE IDENTITY:\n'
      '- Embody {{char}} completely. Every response must reflect their unique personality, speech patterns, '
      'vocabulary level, emotional state, and worldview as defined in their character description.\n'
      '- {{char}} is a living, breathing character with their own desires, fears, opinions, and agency \u2014 '
      'not a servant of {{user}}. They can disagree, have bad days, make mistakes, and act according to their own motivations.\n\n'
      'WRITING CRAFT:\n'
      '- Write in a natural, literary style. Vary sentence length and structure. Avoid repetitive sentence openings.\n'
      '- Show emotions through body language, micro-expressions, vocal tone, and subtle actions rather than stating '
      'feelings directly ("she clenched her jaw" not "she felt angry").\n'
      '- Use all five senses \u2014 sight, sound, smell, touch, taste \u2014 to create vivid, immersive scenes.\n'
      '- Dialogue should feel natural and conversational. Characters can interrupt, trail off, use contractions, '
      'stumble over words, or speak in fragments when emotionally charged.\n'
      '- Weave internal thoughts, environmental details, and physical sensations into responses to create depth.\n'
      '- Match the tone and pacing to the scene: tense moments get short, punchy prose; reflective moments get '
      'slower, more lyrical writing.\n\n'
      'ANTI-SLOP RULES \u2014 AVOID THESE CLICH\u00c9S:\n'
      '- Do NOT use: "a symphony of", "a dance of", "sent shivers down", "electricity coursed through", '
      '"breath hitched", "pupils dilated", "orbs" (for eyes), "ministrations", "mewled", '
      '"the air crackled with", "a masterpiece of", "elicited a moan".\n'
      '- Do NOT start responses with: "I", a sigh, a chuckle, or raising an eyebrow.\n'
      '- Do NOT use purple prose or melodramatic narration. Keep descriptions grounded and specific.\n'
      '- Vary your emotional vocabulary \u2014 don\'t repeat the same descriptors across responses.\n\n'
      'RESPONSE GUIDELINES:\n'
      '- Write 2-5 paragraphs per response unless the scene calls for shorter exchanges.\n'
      '- Always advance the scene meaningfully. Each response should move the story forward through action, '
      'revelation, or emotional development.\n'
      '- End responses at natural pause points that invite {{user}} to react \u2014 don\'t resolve conflicts or '
      'answer your own questions.\n'
      '- Never narrate {{user}}\'s actions, thoughts, dialogue, or emotional reactions. Their agency is sacred.\n'
      '- Never break the fourth wall, mention being an AI, or reference the roleplay as fiction.\n'
      '- Maintain continuity with all previously established facts, character history, and world details.\n\n'
      'DIALOGUE FORMAT:\n'
      '- Use regular text for speech: "Like this," she said.\n'
      '- Use *asterisks* for actions and narration: *She leaned against the doorframe, arms crossed.*\n'
      '- Internal thoughts can be written in italics or described through narration.';

  CharacterCard? get activeCharacter => _activeCharacter;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isLoadingSession => _isLoadingSession;
  String? get currentSessionId => _currentSessionId;
  double get generationProgress => _generationProgress;
  int get tokensGenerated => _tokensGenerated;
  int get maxTokens => _maxTokens;
  bool get isBuffering => _isBuffering;
  GenerationPhase get generationPhase => _generationPhase;

  /// Seconds elapsed since entering the prefill phase. Returns 0 if not prefilling.
  double get prefillElapsedSeconds => _prefillStartTime != null
      ? DateTime.now().difference(_prefillStartTime!).inMilliseconds / 1000.0
      : 0.0;

  /// Cached KoboldCPP performance data from last /api/extra/perf poll.
  Map<String, dynamic>? get lastPerfData => _lastPerfData;

  /// Estimated prompt token count for the current generation (for progress display).
  int get prefillPromptTokens => _prefillPromptTokens;
  bool get isGroupMode => _groupManager?.isActive ?? false;
  GroupChat? get activeGroup => _groupManager?.activeGroup;
  bool get observerMode => _groupManager?.observerMode ?? false;
  bool get autoPlayActive => _groupManager?.autoPlayActive ?? false;
  List<CharacterCard> get groupCharacters =>
      _groupManager?.characters ?? const <CharacterCard>[];

  /// The character who will speak next in group mode.
  /// Fully delegated to GroupTurnManager (supports forced override + both turn orders + Director Mode).
  CharacterCard? get nextCharacter => _groupManager?.nextSpeaker;

  // ── Group RAG / Memory Settings (stored in checkpoint) ───────────────────
  bool get groupRagEnabled => _groupRagEnabled;

  int get groupRetrievalCount => _groupRetrievalCount;

  double get groupMemoryBudgetPercent => _groupMemoryBudgetPercent;

  double getCharacterRAGPriority(String charId) {
    return _groupCharacterRAGPriorities[charId] ?? 1.0;
  }

  Map<String, double> get currentGroupRAGPriorities =>
      Map.unmodifiable(_groupCharacterRAGPriorities);

  void setGroupRAGEnabled(bool value) {
    if (_activeGroup == null) return;
    _groupRagEnabled = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setGroupRetrievalCount(int value) {
    if (_activeGroup == null) return;
    _groupRetrievalCount = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setGroupMemoryBudgetPercent(double value) {
    if (_activeGroup == null) return;
    _groupMemoryBudgetPercent = value;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void setCharacterRAGPriority(String charId, double priority) {
    if (_activeGroup == null) return;
    _groupCharacterRAGPriorities[charId] = priority;
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  void clearCharacterRAGPriority(String charId) {
    _groupCharacterRAGPriorities.remove(charId);
    // (old checkpoint call removed in v30)
    notifyListeners();
  }

  /// True only for regular (non-Director) group chats where the Realism Engine
  /// is enabled. Used by the group sidebar to decide whether to show per-character
  /// emotion / needs indicators.
  bool get isGroupRealismActive =>
      _realismEnabled && isGroupMode && !observerMode;

  /// Phase 3: Hard cap for inter-character relationship tracking.
  /// Per the approved plan, full hidden inter-character dynamics (seeding,
  /// decay, injection, and updates) are **only** performed when the group has
  /// 4 or fewer members. This prevents combinatorial explosion and prompt bloat.
  ///
  /// When the group has 5+ members:
  /// - Inter-character 'relationships' maps remain empty / are ignored.
  /// - All characters still receive full per-speaker realism evaluations for
  ///   their feelings **toward the user** (visible bars continue to work).
  bool get _shouldTrackInterCharacterRelationships {
    if (_activeGroup == null) return false;
    return _groupCharacters.length <= 4;
  }

  /// Returns the current emotion label (e.g. "joy", "sadness", "affection") for
  /// the given character when in a realism-enabled group chat. Returns null otherwise.
  String? getEmotionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['emotion'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns a snapshot of all realism data for a specific character in the
  /// current group (when `isGroupRealismActive` is true). Includes keys like:
  /// 'emotion', 'emotionIntensity', 'affection', 'trust', 'needs', 'fixation',
  /// and (when group size ≤ 4) the hidden 'relationships' map toward other members.
  /// This is primarily for debugging/advanced use; the UI never exposes inter-char data.
  /// Returns null if not in an active realism group or no data for that char.
  Map<String, dynamic>? getRealismStateForGroupCharacter(
    CharacterCard character,
  ) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final data = _groupRealism[id];
    return (data != null && data.isNotEmpty) ? Map.unmodifiable(data) : null;
  }

  // ── Convenient per-character realism accessors for the UI ───────────────

  /// Returns the full needs vector for the given group character.
  /// Empty map if not in group realism mode or no data.
  /// Only official needs keys are returned (legacy bad keys such as 'arousal'/'libido'
  /// from older group data are silently filtered).
  Map<String, int> getNeedsForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return const {};
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['needs'];
    final result = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final v = (raw is Map) ? raw[k] : null;
      if (v is num) {
        result[k] = v.toInt();
      } else {
        // Fill any missing official needs so the UI always shows the complete set.
        // This handles legacy/incomplete group data after previous cleanups.
        result[k] = NeedsSimulation.needDefaults[k] ?? 80;
      }
    }
    return result;
  }

  int getAffectionForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['affection'] as num?)?.toInt() ?? 0;
  }

  int getTrustForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['trust'] as num?)?.toInt() ?? 0;
  }

  String? getFixationForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['fixation'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  int getArousalForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return 0;
    final id = _getCharacterIdFromCard(character);
    return (_groupRealism[id]?['arousal'] as num?)?.toInt() ?? 0;
  }

  String? getEmotionIntensityForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['emotionIntensity'] as String?;
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  /// Returns the remaining lifespan (in turns) for the current fixation of the
  /// given group character, if any. Returns null if not in active group realism
  /// or no fixation data.
  int? getFixationLifespanForGroupCharacter(CharacterCard character) {
    if (!isGroupRealismActive) return null;
    final id = _getCharacterIdFromCard(character);
    final raw = _groupRealism[id]?['fixationLifespan'] as num?;
    return raw?.toInt();
  }

  /// Returns the top N most urgent needs (lowest value first) for the character,
  /// as a list of (needName, value) pairs.
  List<(String, int)> getTopUrgentNeedsForGroupCharacter(
    CharacterCard character, {
    int count = 2,
  }) {
    final needs = getNeedsForGroupCharacter(character);
    if (needs.isEmpty) return const [];

    final sorted = needs.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // lowest = most urgent

    return sorted.take(count).map((e) => (e.key, e.value)).toList();
  }

  // ── Hidden inter-character relationship helpers (Phase 0 foundation) ─────
  // These track how group members feel about *each other* (invisible to UI).
  // All visible bars/UI continue to reflect only feelings toward the user.
  // Full inter-char tracking is hard-capped at groups of 4 or fewer (enforced at usage sites).

  /// Returns the map of hidden inter-character relationship scores for the given
  /// group character (otherCharId → score in -300..+300 range, same scale as bond).
  /// Empty map if not in group realism mode or no data yet.
  /// These values are strictly internal and are never exposed in any user-facing UI.
  ///
  /// Backward-compat: If an old checkpoint is missing the 'relationships' key for
  /// a character, we naturally return empty (no migration needed).
  // (inter-char relationship shims excised in final cleanup; use relationshipService directly)

  /// Clears the per-character realism state (emotion, bond/affection, trust,
  /// arousal, fixation, needs vector, and any hidden inter-character relationships)
  /// for the specified character in the current group chat session.
  /// Persists the change via the hidden checkpoint.
  /// Safe to call even if no prior state existed for the character.
  void resetRealismForGroupCharacter(CharacterCard character) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(character);
    if (_groupRealism.containsKey(id)) {
      _groupRealism.remove(
        id,
      ); // also clears hidden 'relationships' toward other group members
      // (old checkpoint call removed in v30)
      debugPrint('[GroupRealism] Reset per-character state for $id');
      notifyListeners();
    }
  }

  double get tokensPerSecond {
    if (_tokenTimestamps.length < 2) return 0.0;
    // Use rolling window: tokens in the last 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 3));
    final recent = _tokenTimestamps.where((t) => t.isAfter(cutoff)).length;
    if (recent < 2) {
      // Fallback to overall average
      if (_generationStartTime == null || _tokensGenerated == 0) return 0.0;
      final elapsed =
          now.difference(_generationStartTime!).inMilliseconds / 1000.0;
      return elapsed > 0 ? _tokensGenerated / elapsed : 0.0;
    }
    final windowStart = _tokenTimestamps.where((t) => t.isAfter(cutoff)).first;
    final windowElapsed = now.difference(windowStart).inMilliseconds / 1000.0;
    return windowElapsed > 0 ? recent / windowElapsed : 0.0;
  }

  int _greetingIndex = 0;
  int get greetingIndex => _greetingIndex;

  ChatService(
    this._koboldService,
    this._userPersonaService,
    this._storageService,
    this._worldRepository,
  );

  /// Set the database instance after construction.
  void setDatabase(AppDatabase db) {
    _db = db;
  }

  String get authorNote => _authorNote;
  int get authorNoteStrength => _authorNoteStrength;

  /// Returns the Author's Note text (if any) stored specifically for this
  /// character within the current *group* chat. Uses the stable char ID.
  /// Returns '' if not in group mode or no per-character note has been set.
  /// (The group's authorNoteStrength is used for formatting during injection.)
  String getAuthorNoteForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return '';
    final id = _getCharacterIdFromCard(c);
    return _groupAuthorNotes[id] ?? '';
  }

  /// Returns the strength (1-10) for this character's Author's Note.
  /// Falls back to the group's current authorNoteStrength if no per-character
  /// strength has been explicitly set.
  int getAuthorNoteStrengthForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return _authorNoteStrength;
    final id = _getCharacterIdFromCard(c);
    return _groupAuthorNoteStrengths[id] ?? _authorNoteStrength;
  }

  /// Sets or clears a per-character Author's Note for the given card while in
  /// a group chat. The value is persisted via the hidden group state checkpoint.
  /// [strength] is accepted for forward compatibility (per-note strength) but
  /// currently all per-char notes use the group's authorNoteStrength for
  /// prompt formatting. Pass empty [note] to clear.
  void setAuthorNoteForGroupCharacter(
    CharacterCard c,
    String note, {
    int? strength,
  }) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(c);
    final trimmed = note.trim();

    if (trimmed.isEmpty) {
      _groupAuthorNotes.remove(id);
      _groupAuthorNoteStrengths.remove(id);
    } else {
      _groupAuthorNotes[id] = trimmed;
      // Store per-character strength if provided, otherwise fall back to group default
      final effectiveStrength = strength ?? _authorNoteStrength;
      _groupAuthorNoteStrengths[id] = effectiveStrength;
    }

    // (old checkpoint call removed in v30)
    _saveChat();
    notifyListeners();
  }

  /// Returns the system prompt (if any) stored specifically for this character
  /// *within the current group chat*. This is completely separate from the
  /// character's normal `systemPrompt` on their card (used in 1:1 chats).
  /// Returns '' if not in a group or no per-character group prompt has been set.
  /// When non-empty, this value wins over the character's normal systemPrompt
  /// for prompt construction inside this group.
  String getSystemPromptForGroupCharacter(CharacterCard c) {
    if (_activeGroup == null) return '';
    final id = _getCharacterIdFromCard(c);
    return _groupCharacterSystemPrompts[id] ?? '';
  }

  /// Sets or clears a per-character system prompt override for the given
  /// character while inside a group chat. The value is persisted via the
  /// hidden group state checkpoint (no DB schema change).
  /// This affects only the current group. Pass empty [prompt] to clear.
  /// The provided prompt takes precedence over the character's normal
  /// `systemPrompt` when this character speaks in the group.
  void setSystemPromptForGroupCharacter(CharacterCard c, String prompt) {
    if (_activeGroup == null) return;
    final id = _getCharacterIdFromCard(c);
    final trimmed = prompt.trim();

    if (trimmed.isEmpty) {
      _groupCharacterSystemPrompts.remove(id);
    } else {
      _groupCharacterSystemPrompts[id] = trimmed;
    }

    // (old checkpoint call removed in v30)
    _saveChat();
    notifyListeners();
  }

  Map<String, int> get lastPromptBudget => _lastPromptBudget;
  String get lastAssembledPrompt => _lastAssembledPrompt;
  int get contextSize =>
      _sessionGenSettings.resolveContextSize(_storageService);

  /// Per-session generation parameter overrides. The dialog reads/writes this.
  ChatGenerationSettings get sessionGenSettings => _sessionGenSettings;
  set sessionGenSettings(ChatGenerationSettings value) {
    _sessionGenSettings = value;
    _saveChat();
    notifyListeners();
  }

  String? get parentSessionId => _parentSessionId;
  int? get forkIndex => _forkIndex;
  String? get sessionName => _sessionName;
  String? get sessionDescription => _sessionDescription;
  String get summary => _summary;
  bool get summaryPaused => _summaryPaused;
  int get summaryLastIndex => _summaryLastIndex;
  bool get isSummaryGenerating => _isSummaryGenerating;
  // Public access to extracted domain services (final shim migration + cleanup).
  // Callers (UI sidebars, tests, chance overlay, group settings, etc.) now use direct:
  //   chat.relationshipService.affectionScore / .trustLevel / shortTermTierName etc.
  //   chat.timeService.timeOfDay / .dayCount / .setPassageOfTimeEnabled(...)
  //   chat.nsfwService.nsfwCooldownEnabled / .arousalLevel / .setNsfwCooldownEnabled
  //   chat.chaosModeService.chaosModeEnabled / .chaosPressure / .hasPendingChaosEvent
  //   chat.needsSimulation.vector / .pendingCatastrophe
  //   chat.expressionService.currentExpressionLabel / .resolveExpressionAvatar / .setManualExpression
  // God owns the late finals (for 1:1+group dispatch, _groupRealism load/save, cbs, notify, reset hygiene).
  // Barrel not updated (internal; <3 public cross locations precedent).
  RelationshipService get relationshipService => _relationshipService;
  ExpressionService get expressionService => _expressionService;
  TimeService get timeService => _timeService;
  NsfwService get nsfwService => _nsfwService;
  ChaosModeService get chaosModeService => _chaosModeService;
  NeedsSimulation get needsSimulation => _needsSimulation;

  // Thin public surface for flat members still read/written by UI/pages/dialogs
  // (chat.chaosPressure, chat.activeFixation, chat.pendingTrustRepair, chat.currentExpressionLabel,
  // chat.resolveExpressionAvatar, per "thin delegation here; full XXX in the leaf" + 0 new god _ privates).
  // Full impl in the respective *Service (chaos_mode_service, relationship_service, expression_classifier in chat/).
  // 1:1 vs group parity via the services' cbs + god impersonation dance (unchanged).
  int get chaosPressure => _chaosModeService.chaosPressure;
  String get activeFixation => _relationshipService.activeFixation;
  bool get pendingTrustRepair => _relationshipService.pendingTrustRepair;
  String? get currentExpressionLabel =>
      _expressionService.currentExpressionLabel;
  AvatarImage? resolveExpressionAvatar(
    CharacterCard character, {
    bool rerollIfSame = false,
  }) => _expressionService.resolveExpressionAvatar(
    character,
    rerollIfSame: rerollIfSame,
  );

  bool get realismEnabled => _realismEnabled;

  /// True when the Realism Engine (and Needs) should actually run for the
  /// current chat mode. In group chats this is only true when *not* in
  /// Director/observerMode (per design — Director is narrative control,
  /// not simulation).
  bool get _realismActiveThisMode =>
      _realismEnabled && (_activeGroup == null || !_observerMode);

  bool get isEvaluatingRealism => _isEvaluatingRealism;
  bool get isCancellingRealismEval => _isCancellingRealismEval;
  bool get isProcessingGreeting => _isProcessingGreeting;
  String get realismEvalStreamText => _realismEvalStreamText;

  // Verifier phase (for overlay header "🕵️ Verifying Realism output" + pass progress, and bubble chip data source).
  // God coordination only; leaf drives via cb thins (no new god void _).
  bool get isVerifyingRealism => _isVerifyingRealism;
  int get verificationPass => _verificationPass;
  int get verificationMaxPasses => _verificationMaxPasses;

  /// Stream text with any  blocks stripped (for display).
  String get realismEvalStreamTextClean =>
      _stripThinkBlocks(_realismEvalStreamText);
  String get characterEmotion => _characterEmotion;

  String getCurrentEmotion() => _characterEmotion;

  String get emotionIntensity => _emotionIntensity;

  /// True if the realism engine has already captured a meaningful baseline
  /// (emotion or bond score). Used to avoid redundant retroactive scans.
  bool get _hasRealismBaseline =>
      _characterEmotion.isNotEmpty ||
      _relationshipService.affectionScore != 0 ||
      _nsfwService.arousalLevel != 0 ||
      _relationshipService.activeFixation.isNotEmpty;

  /// Whether the per-session Needs (Sims-style) simulation is active.
  /// When true and `enjoysLowHygiene` is also true, low hygiene becomes desirable.
  ///
  /// When enabled, [needsVector] holds the current 0–100 levels and the engine
  /// performs decay, prompt injection, and LLM-verified fulfillment restores.
  /// New chats seed this from the character's [FrontPorchExtensions.needsSimEnabled].
  /// Disabling mid-chat clears the vector; historical snapshots cannot re-enable it.
  bool get needsSimEnabled => _needsSimEnabled;

  /// Returns whether the currently active character enjoys low hygiene.
  /// We always prefer the live value from the character's FrontPorchExtensions
  /// so that toggling the setting on the character immediately affects any
  /// already-loaded chats (no database change required).
  bool get enjoysLowHygiene {
    return _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ??
        _enjoysLowHygiene;
  }

  /// Re-reads the "Enjoys low hygiene" preference from the currently active
  /// character's FrontPorchExtensions. Call this after editing the character
  /// so that existing chats immediately pick up the new setting without a
  /// database change.
  void refreshEnjoysLowHygieneFromActiveCharacter() {
    if (_activeCharacter != null) {
      _enjoysLowHygiene =
          _activeCharacter!.frontPorchExtensions?.enjoysLowHygiene ?? false;
      notifyListeners();
    }
  }

  bool get chaosNsfwEnabled => _chaosModeService.chaosNsfwEnabled;

  /// Non-null for exactly one notification cycle. UI reads then calls clearChanceTimeEvent().
  String? get pendingChanceTimeEvent => _pendingChanceTimeEvent;

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger => _chanceTimePendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => _chaosModeService.hasPendingChaosEvent;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() => _chanceTimePendingTrigger = false;

  // (nsfw/relationship long list of @Dep shims excised in final cleanup; use nsfwService / relationshipService)

  /// Human-readable mood label containing exact emotion string and valence direction.
  String get moodLabel {
    if (_characterEmotion.isEmpty) return 'Neutral';
    final capEmotion =
        _characterEmotion.substring(0, 1).toUpperCase() +
        _characterEmotion.substring(1);
    final intensity = _emotionIntensity.isNotEmpty
        ? ' ($_emotionIntensity)'
        : '';
    return '$capEmotion$intensity';
  }

  /// Returns the standard expression label for the current emotion.
  ///
  /// If a manual expression is set via [setManualExpression], returns that.
  /// When classification mode is 'onnx', uses the ONNX classifier result.
  /// Otherwise maps the nuanced emotion to a standard label
  /// using [EmotionLabels.nuancedToStandard].
  // (currentExpressionLabel / resolveExpressionAvatar / setManualExpression @Dep shims excised; use expressionService; main wiring note: update main if using the removed setExpressionClassifierService shim)

  void setAuthorNote(String note, {int? strength}) {
    _authorNote = note;
    if (strength != null) _authorNoteStrength = strength;
    _saveChat();
    notifyListeners();
  }

  /// Build the Author's Note block with strength-modulated wrapper text.
  /// Strength 1–3: subtle suggestion, 4–7: standard, 8–10: urgent directive.
  String _buildAuthorNoteBlock() {
    if (_authorNote.isEmpty) return '';
    if (_authorNoteStrength <= 3) {
      return '[Author\'s Note (gentle suggestion): $_authorNote]\n';
    } else if (_authorNoteStrength <= 7) {
      return '[Author\'s Note: $_authorNote]\n';
    } else {
      return '[Author\'s Note (IMPORTANT — apply immediately): $_authorNote]\n';
    }
  }

  /// Set the CharacterRepository so group mode can look up characters.
  void setCharacterRepository(CharacterRepository repo) {
    _characterRepository = repo;
  }

  /// Wired by main.dart so that group member loading works for all call sites
  /// (creation, home taps, fork, etc.) without every caller having to pass the repo.
  void setGroupChatRepository(GroupChatRepository repo) {
    _groupChatRepository = repo;
  }

  /// Build the user persona block for the generation prompt.
  /// Layered: user's self-description is ground truth, learned facts are additive.
  /// When the embedding service is available, selects only the most relevant facts
  /// for the current conversation context instead of injecting all facts.
  Future<String> _buildUserPersonaBlock(String userName) async {
    final persona = _userPersonaService.persona;
    final personaText = persona.persona.trim();
    final allFacts = persona.learnedFacts;

    // Nothing to inject
    if (personaText.isEmpty && allFacts.isEmpty) return '';

    // Select relevant facts using embeddings if available
    List<String> facts;
    if (allFacts.length > 15 && _memoryService != null) {
      // Build context from last few messages
      final recentContext = _messages.reversed
          .take(3)
          .map((m) => '${m.sender}: ${m.displayText}')
          .join('\n');
      facts = await _userPersonaService.getRelevantFacts(
        conversationContext: recentContext,
        embedService: _memoryService!.embeddingService,
        maxFacts: 15,
      );
    } else {
      facts = List<String>.from(allFacts);
    }

    final buf = StringBuffer();
    final safeUserName = userName.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();
    final safePersonaText = personaText
        .replaceAll(RegExp(r'[\n\r"]'), ' ')
        .trim();
    buf.writeln("$safeUserName's Persona: $safePersonaText");

    if (facts.isNotEmpty) {
      buf.writeln(
        '[Discovered traits — observations learned from conversation. '
        'The user\'s self-description above takes priority if there is a conflict.]',
      );
      for (final fact in facts) {
        final safeFact = fact.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();
        buf.writeln('- $safeFact');
      }
    }
    buf.writeln();
    return buf.toString();
  }

  /// Set the LLMProvider after construction (to break circular dependency in provider tree).
  void setLLMProvider(LLMProvider provider) {
    _llmProvider = provider;
  }

  /// Set the TtsService after construction (for TTS-aware auto-play delay).
  void setTtsService(TtsService service) {
    _ttsService = service;
  }

  /// Set the MemoryService after construction (for RAG memory retrieval).
  void setMemoryService(MemoryService service) {
    _memoryService = service;
  }

  /// Set the ExpressionClassifierService after construction (for ONNX emotion classification).
  void setExpressionClassifierService(ExpressionClassifierService service) =>
      _expressionService.setExpressionClassifierService(service);

  /// Wait for TTS to finish speaking, then apply the configured delay before auto-play.
  void _waitForTtsThenContinue() {
    if (!(_groupManager?.autoPlayActive ?? false) ||
        !(_groupManager?.observerMode ?? false)) {
      return;
    }

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!(_groupManager?.autoPlayActive ?? false) ||
          !(_groupManager?.observerMode ?? false)) {
        timer.cancel();
        return;
      }
      if (_ttsService == null || !_ttsService!.isSpeaking) {
        timer.cancel();
        final delayMs = ((_groupManager?.directorDelaySec ?? 15.0) * 1000)
            .round();
        Future.delayed(Duration(milliseconds: delayMs), () {
          if ((_groupManager?.autoPlayActive ?? false) && !_isGenerating) {
            _autoPlayNext();
          }
        });
      }
    });
  }

  Future<void> setActiveCharacter(CharacterCard? character) async {
    // Cancel any in-flight generation before switching context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // If same character is already active and has messages, just refresh
    // the character reference (in case fields were edited) but skip the
    // expensive full re-initialization (message clearing, session reload).
    if (_activeCharacter?.name == character?.name &&
        _activeCharacter?.dbId == character?.dbId &&
        _messages.isNotEmpty) {
      _activeCharacter = character;
      notifyListeners();
      return;
    }

    // Clear group mode when switching to 1:1 AND reset author note for new session context
    _authorNote = '';
    _authorNoteStrength = 4;
    _groupManager?.leaveGroup();
    _groupManager = null;
    _groupRealism = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupRagEnabled = true;
    _groupRetrievalCount = 8;
    _groupMemoryBudgetPercent = 10.0;
    _groupCharacterRAGPriorities = {};

    _activeCharacter = character;

    // Auto-start local backend (Kobold or Pseudo-Remote) when entering a chat
    // so the user never has to manually start it just to talk.
    _llmProvider?.ensureManagedBackendIsRunning();

    // If extensions are missing (e.g., app was restarted after DB load that
    // didn't carry over PNG extensions), reload the PNG to get V2.5 card data.
    if (_activeCharacter != null &&
        _activeCharacter!.frontPorchExtensions == null &&
        _activeCharacter!.imagePath != null) {
      try {
        final v2Service = V2CardService();
        final reloaded = await v2Service.readCard(_activeCharacter!.imagePath!);
        if (reloaded != null && reloaded.frontPorchExtensions != null) {
          _activeCharacter!.frontPorchExtensions =
              reloaded.frontPorchExtensions;
          _activeCharacter!.rawExtensions = reloaded.rawExtensions;
          debugPrint(
            '[ChatService] Reloaded frontPorchExtensions from PNG for ${_activeCharacter!.name}',
          );
        }
      } catch (e) {
        debugPrint('[ChatService] Failed to reload PNG extensions: $e');
      }
    }

    // Note: evolved personality/scenario are now loaded inside _loadLastSession()
    // (which runs below) so they are scoped to the session, not the character.
    debugPrint(
      '[ChatService] 🟡 setActiveCharacter: clearing messages '
      '(had ${_messages.length}) for ${character?.name}, loading session...',
    );
    _messages.clear();
    _currentSessionId = null;
    _summary = '';
    _summaryLastIndex = 0;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric to _isSummaryGenerating; incomplete zeroing... now complete (see CLAUDE.md); see keep-sync + summary_service)
    _isSummaryGenerating =
        false; // explicit secondary zero on setActiveCharacter (incomplete zeroing of secondary config on ... now complete; see keep-sync + summary_service)
    // Clear fork/branch state so it doesn't leak from previous character
    // into a fresh character's first session (see startNewChat for details).
    _parentSessionId = null;
    _forkIndex = null;
    _isLoadingSession = true;
    notifyListeners();

    if (_activeCharacter != null) {
      // Lorebook trigger reset via extracted service (keeps the keep-sync reset sites correct
      // without god privates; constants skipped, non-const zeroed for char + attached worlds).
      // See lorebook_scanner.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + summary_service (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
      _lorebookScanner.resetLorebookTriggerState();

      // Reset realism state to prevent bleeding from previous character.
      // Keep the reset sites (startNewChat 1:1+group now with explicit lorebook reset in both branches, load*Session paths incl. empty for groups, setActiveGroup, setActiveCharacter, delete flows, ext-seed, fork/insert)
      // in sync when moving more state in later Stage 3 steps. See needs_simulation.dart for the
      // current owner of vector + buffers (and _needsSimEnabled/_enjoysLowHygiene control fields).
      // Relationship + Expression + Time + Nsfw + LorebookScanner via service reset helpers (expression: manual/caches/onnx/lastAvatar/random;
      // time: clock/day/passage/turns/anchor + narrative weekday; nsfw: cooldown/arousal/tier; lorebook: triggers/depth on entries).
      // All secondary time/nsfw/lorebook config zeroed on fresh group/0-session paths.
      final prevArousal = _nsfwService.arousalLevel;
      final prevFixation = _relationshipService.activeFixation;
      final prevFixationLife = _relationshipService.fixationLifespan;
      _needsSimEnabled = false;
      _enjoysLowHygiene = false;
      _needsSimulation.clearVector();
      _needsSimulation.resetBuffers();
      _realismEnabled = false;
      _characterEmotion = '';
      _emotionIntensity = '';
      // Time reset via extracted service (keeps multiple reset blocks in sync).
      // See time_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + summary_service (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
      _timeService.resetForFreshChat();
      // Chaos reset via extracted service (keeps multiple reset blocks in sync).
      // See chaos_mode_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + summary_service (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
      _chaosModeService.resetForFreshChat();
      // Nsfw reset via extracted service (keeps multiple reset blocks in sync).
      // See nsfw_service.dart and "keep reset blocks" comments (now lists needs/chaos/relationship/expression/time/nsfw/lorebook_scanner + prompt_injection (stateless builders; no reset calls needed) + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + summary_service (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
      _nsfwService.resetForFreshChat();
      // Lorebook already reset above via _lorebookScanner (keeps blocks in sync; see cross-ref comment at top of this reset).
      _relationshipService.resetForFreshChat();
      _expressionService.resetForFreshChat();
      _moodDecayCounter = 0;
      _greetingEvalPending = false;
      _isProcessingGreeting = false;
      _pendingRealismMetadata = null;
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion =
          false; // secondary objective flag zero on setActiveCharacter main path (incomplete zeroing hygiene; keep reset blocks)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero on setActiveCharacter main path (incomplete zeroing... now complete (see CLAUDE.md); fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero on setActiveCharacter main path (incomplete zeroing... now complete (see CLAUDE.md); evolution_service (stateless or prompt-only; no reset calls needed); cross-ref setActiveCharacter:1572 + full keep-sync lists + " ; no extra zero code, live read; now complete for this secondary config too)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)"
      debugPrint(
        '[ChatService] setActiveCharacter: Reset realism state (baseline + runtime transients cleared; was: arousal=$prevArousal, fixation=$prevFixation/$prevFixationLife)',
      );

      // Try to load last session
      await _loadLastSession();

      // If no session loaded, start fresh
      if (_messages.isEmpty) {
        // Seed Realism Engine state from V2.5 card extensions (new conversations only)
        if (_activeCharacter!.frontPorchExtensions != null) {
          final ext = _activeCharacter!.frontPorchExtensions!;
          _realismEnabled = ext.realismEnabled;
          // Card-seed bypass (rec 1 from PR #47): use seedFromCardV2OrExt (plain .clamp only,
          // no _migrate*) because V2.5 cards + creator UI author shortTermBond/longTermBond on the
          // *current* ±300 scale (see models/character_card.dart:31-32 + FrontPorchExtensions).
          // Legacy *2 migration must stay *only* on _loadLastSession loadScalars + migrate* wrappers
          // + applyLegacyShortTermMigrationIfNeeded paths (and the public migrate surface).
          // This was the root cause of bond-doubling (e.g. authored 55 -> 110) on every fresh 1:1
          // card import / 0-session setActive / startNew. 1:1 only; group per-speaker paths were
          // never affected (used loadRelationshipScalarsForSpeaker etc). See relationship_service.dart
          // seedFromCardV2OrExt + god keep-sync comments (full list) + cross-ref setActiveCharacter:1572.
          _relationshipService.seedFromCardV2OrExt(
            shortTermBond: ext.shortTermBond,
            longTermBond: ext.longTermBond,
            trustLevel: ext.trustLevel,
          );
          // Time seed via extracted service (keeps reset/seed blocks in sync with startNewChat etc).
          // Global ceiling applied before passing (see time_service.seed doc).
          _timeService.seedFromV2OrExt(
            dayCount: ext.dayCount.clamp(1, 9999),
            timeOfDay: ext.timeOfDay,
            passageOfTimeEnabled:
                ext.passageOfTimeEnabled &&
                _storageService.realismSettings.passageOfTimeDefault,
          );
          _characterEmotion = ext.characterEmotion;
          _emotionIntensity = ext.emotionIntensity;
          _nsfwService.seedFromV2OrExt(
            nsfwCooldownEnabled: ext.nsfwCooldownEnabled,
          );
          _chaosModeService.seedFromGroupOrExt(ext.chaosModeEnabled, false);
          _needsSimEnabled = ext.needsSimEnabled;
          _enjoysLowHygiene = ext.enjoysLowHygiene;
          if (_needsSimEnabled) {
            // Brand new conversation for this character (no prior session loaded):
            // seed from card baselines (falls back to needDefaults when the card has no baselines).
            _needsSimulation.initializeFreshWithDefaults({
              'hunger': ext.needsBaselineHunger,
              'bladder': ext.needsBaselineBladder,
              'energy': ext.needsBaselineEnergy,
              'social': ext.needsBaselineSocial,
              'fun': ext.needsBaselineFun,
              'hygiene': ext.needsBaselineHygiene,
              'comfort': ext.needsBaselineComfort,
            });
          } else {
            _needsSimulation.clearVector();
          }
          // Tiers maintained by service after seedFromCardV2OrExt (or V2OrExt for other leaves).
          debugPrint(
            '[ChatService] V2.5 extensions seeded: realism=$_realismEnabled, '
            'bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}, day=${_timeService.dayCount}, time=${_timeService.timeOfDay}',
          );

          // Seed initial quest/task as a primary objective
          if (ext.currentTask.isNotEmpty) {
            // Defer so the session ID is ready before the DB write
            Future.microtask(() async {
              await setObjective(ext.currentTask, isPrimary: true);
              debugPrint(
                '[ChatService] V2.5 seeded initial task: ${ext.currentTask}',
              );
            });
          }
        }

        if (_activeCharacter!.firstMessage.isNotEmpty) {
          _messages.add(
            ChatMessage(
              text: _buildFirstMessage(_activeCharacter!),
              sender: _activeCharacter!.name,
              isUser: false,
            ),
          );
          // Scan first message for lore (thin delegation to extracted scanner).
          _lorebookScanner.scanLorebook(_messages.last.text);
        }
        // Note: for the direct 0-session setActiveCharacter path (fresh import via home grid <=1 session),
        // _greetingEvalPending is left false here. The post-greeting baseline eval is scheduled only
        // in startNewChat (for explicit New Chat flows). Fresh-import cards rely on the retro path
        // in setRealismEnabled (or manual enable after first messages) when _hasRealismBaseline==false.
        // This matches pre-existing behavior for the import entry point; the critical bleed fix
        // ensures the baseline check is now correctly false for no-ext cards.
        // Save the initial message session
        _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
        await _saveChat();
        _activeObjectives = [];
        _messagesSinceLastCheck = 0;
        _isCheckingCompletion =
            false; // zero secondary in empty session subpath of setActiveCharacter (per incomplete zeroing fix)
        _isSummaryGenerating =
            false; // secondary zero in empty subpath of setActiveCharacter (incomplete zeroing... now complete (see CLAUDE.md))
        _userMessagesSinceLastPeriodicEval = 0;
        _isExtractingFacts =
            false; // secondary fact flag + counter zero in empty subpath of setActiveCharacter (incomplete zeroing ... now complete; fact_extraction)
        _isEvolvingCharacter = false;
        _evolutionStatus = '';
        _evolutionError =
            ''; // explicit evo flag/status/error zero in empty subpath of setActiveCharacter (incomplete zeroing... now complete (see CLAUDE.md); evolution_service (stateless or prompt-only; no reset calls needed); cross-ref setActiveCharacter:1572 + " ) + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)"
      }
      // Load active objectives for this session (must be after _loadLastSession
      // so _currentSessionId is set)
      await _loadActiveObjectives(); // Awaited (was fire-and-forget); root fix for post-dispose notify races in tests + rapid switches. Central _disposed + notifyListeners override (rec 2) now protects residual unawaited/microtask paths + any other notify-after-async in god/services (see _disposed decl, overrides at end of class, and cleaned per-site guard in _loadActiveObjectives).
    }
    _isLoadingSession = false;
    notifyListeners();
  }

  /// Enter group chat mode with the given GroupChat definition.
  Future<void> setActiveGroup(
    GroupChat group, {
    GroupChatRepository? groupRepo,
  }) async {
    // Cancel any in-flight generation before switching context AND reset author note for new session context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // Reset author notes and summary when starting fresh chat/group (will be overridden if loading existing session)
    _authorNote = '';
    _authorNoteStrength = 4;
    _summary = '';
    _summaryLastIndex = 0;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; incomplete zeroing... now complete (see CLAUDE.md); see keep-sync + summary_service)
    _isSummaryGenerating =
        false; // explicit secondary zero on setActiveGroup (incomplete zeroing ... now complete; keep-sync lists + summary_service + " ; authority for needs deltas thin path)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)"
    _groupRealism = {};
    _groupDecayRates = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupRagEnabled = true;
    _groupRetrievalCount = 8;
    _groupMemoryBudgetPercent = 10.0;
    _groupCharacterRAGPriorities = {};

    // Path B: Load per-character group system prompts from the clean model field
    _groupCharacterSystemPrompts = Map<String, String>.from(
      group.characterSystemPrompts,
    );

    if (_characterRepository == null) return;

    // Clear 1:1 mode
    _activeCharacter = null;
    // Defensive: zero key 1:1 scalars so rapid 1:1↔group toggles cannot observe
    // stale values in the brief window before group per-speaker loads take over.
    // (Full reset happens on return to any 1:1 via setActiveCharacter.)
    _characterEmotion = '';
    // Relationship scalars/fixation (affection/trust/tiers/fixation/spatial/pending) via extracted service.
    // Expression manual/caches via service. Time (clock/day/passage/anchor/turns) via service.
    // Nsfw (arousal/cooldown) via service.
    // Lorebook triggers via scanner (for group fresh/0-session hygiene; parallels time/nsfw defensive zeros).
    // Reset hygiene (see CLAUDE.md "keep reset blocks in sync" + "incomplete zeroing of secondary config on group/0-session/new-chat now complete" at *all* ~15+ sites + both startNew explicit; authority live ext no scalar; buffer removal complete; leaves stateless/prompt-only no reset calls; void_=15).
    // (cross-ref setActiveCharacter)
    _relationshipService.resetForFreshChat();
    _expressionService.resetForFreshChat();
    _timeService.resetForFreshChat();
    _nsfwService.resetForFreshChat();
    _lorebookScanner.resetLorebookTriggerState();

    // Auto-start local backend when entering a group chat
    _llmProvider?.ensureManagedBackendIsRunning();

    debugPrint(
      '[ChatService] 🟡 setActiveGroup: clearing messages '
      '(had ${_messages.length}) for group ${group.name}',
    );
    _messages.clear();
    _currentSessionId = null;
    // Clear fork/branch state so it doesn't leak across group switches
    // (see startNewChat and setActiveCharacter for rationale).
    _parentSessionId = null;
    _forkIndex = null;
    _isLoadingSession = true;
    notifyListeners();

    // Resolve characters from decoupled private members (GroupMembers table + private avatars dir).
    // Prefer passed repo, then wired one, then direct DB query as ultimate fallback
    // (ensures members appear in chat even if DI wiring or caller is incomplete).
    List<GroupMember> memberRows = const [];
    try {
      final effectiveGroupRepo = groupRepo ?? _groupChatRepository;
      if (effectiveGroupRepo != null) {
        memberRows = await effectiveGroupRepo.getMembersForGroup(group.id);
      } else {
        final db = await AppDatabase.instance();
        final rows = await db.getGroupMembers(group.id);
        memberRows = rows.map(GroupMember.fromRow).toList();
      }
    } catch (e) {
      debugPrint(
        '[ChatService] Failed to load group members for ${group.id}: $e',
      );
      memberRows = const [];
    }

    final resolved = <CharacterCard>[];
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          group.id,
          'avatars',
          m.avatarFilename!,
        );
        // Include the member even if the avatar file is missing (defensive for groups created
        // from sources that had no avatar, or partial copy failures). The UI already degrades
        // gracefully to a colored letter/initial when the image can't be loaded.
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        } else {
          // Still include them so the count and sidebar are correct; they just won't have a face.
          debugPrint(
            '[ChatService] Group member ${m.name} has no avatar file at $p — including without image',
          );
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      } else {
        // No avatar filename at all — still include so the user sees the member.
        resolved.add(m.toCharacterCard(resolvedImagePath: ''));
      }
    }

    // Hand off to the turn manager (single source of truth for group turn state)
    _groupManager ??= GroupTurnManager();
    _groupManager!.enterGroup(
      group,
      resolved,
      startInDirectorMode: group.directorMode,
    );

    // Seed group definition defaults for Chaos (can be overridden by per-session values loaded below).
    // This makes the chaosModeEnabled / chaosNsfwEnabled on the GroupChat model actually functional.
    _chaosModeService.seedFromGroupOrExt(
      group.chaosModeEnabled,
      group.chaosNsfwEnabled,
    );

    // v30: For newly created group sessions (no prior state), seed from the group's default realism data.
    // (The actual load of any prior session state happens in _loadLastSession below.)
    if (_messages.isEmpty && _activeGroup != null) {
      _loadGroupRealismStateFromSession(null);

      // Promote the group definition's realism/needs intent on first entry.
      // The creator (and Group Card import) express "realism on" by writing non-empty
      // defaultMemberRealismState. Without this promotion, the master flag stays false
      // (its Dart initializer), the first session is saved with realism off, and both
      // isGroupRealismActive and all per-char getters return nothing.
      if (_groupRealism.isNotEmpty) {
        _realismEnabled = true;
        // Infer needs from whether the seeded per-char states actually contain needs data.
        // (Creator omits the 'needs' sub-map entirely when the user disabled Needs in the wizard.)
        _needsSimEnabled = _groupRealism.values.any((state) {
          final n = state['needs'];
          return n is Map && n.isNotEmpty;
        });
        if (_needsSimEnabled) {
          // Seed from group definition's per-char needs baselines (falls back to 80 when absent).
          final defaults = <String, int>{
            'hunger': 80, 'bladder': 80, 'energy': 80, 'social': 80,
            'fun': 80, 'hygiene': 80, 'comfort': 80,
          };
          _needsSimulation.initializeFreshWithDefaults(defaults);
        }
        debugPrint(
          '[GroupRealism] Promoted definition realism/needs on fresh group entry '
          '(realism=$_realismEnabled, needs=$_needsSimEnabled, chars=${_groupRealism.length})',
        );
      }
    }

    // Seed objectives that came from an imported Group Card (one-time)
    await _seedImportedMemberObjectivesIfPresent();

    // Lorebook trigger reset via extracted service (group path; see setActiveCharacter for the 1:1 counterpart + keep-sync cross-refs).
    // See "keep reset blocks in sync" comments (now explicitly lists needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) alongside prior services; incomplete zeroing now complete).
    // (cross-ref setActiveCharacter:1572)
    _lorebookScanner.resetLorebookTriggerState();

    // Zero secondary objective config on group fresh entry (before loadLast + _loadObjectivesForCurrentSpeaker); see decl + keep reset + incomplete zeroing now complete.
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; group fresh entry zero)
    _isSummaryGenerating =
        false; // secondary flag zero for summary_service (stateless/prompt-only; see incomplete zeroing ... now complete + keep-sync lists)
    _userMessagesSinceLastPeriodicEval = 0;
    _isExtractingFacts =
        false; // secondary fact flag + counter zero on group fresh entry (incomplete zeroing ... now complete; fact_extraction)
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError =
        ''; // explicit evo flag/status/error zero on group fresh entry (incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed); cross-ref setActiveCharacter:1572)

    // Try to load last session for this group
    await _loadLastSession();

    // Load the objectives for whoever is the initial next speaker (or first char)
    if (_activeGroup != null) {
      await _loadObjectivesForCurrentSpeaker();
    }

    // Seed objectives that came from an imported Group Card (one-time), in case it wasn't caught above
    await _seedImportedMemberObjectivesIfPresent();

    // If no session, create a greeting
    if (_messages.isEmpty && _groupCharacters.isNotEmpty) {
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (group.firstMessage.isNotEmpty) {
        // Use custom group first message — attribute to "Narrator" or group name
        greetingText = _applyUserReplacement(group.firstMessage);
        greetingSender = group.name;
        greetingCharId = null;
      } else {
        // Fall back to first character's greeting
        final first = _groupCharacters.first;
        greetingText = first.firstMessage.isNotEmpty
            ? _buildFirstMessage(first)
            : '';
        greetingSender = first.name;
        greetingCharId = _getCharacterIdFromCard(first);
      }

      if (greetingText.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        // Thin delegation to scanner (group greeting scan).
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
    }

    // Load evolved fields for all group characters
    _loadGroupEvolvedFields();

    _isLoadingSession = false;
    notifyListeners();
  }

  /// Fork the current 1:1 chat into a new group chat, copying all messages.
  /// The original 1:1 session remains untouched.
  Future<GroupChat?> forkToGroupChat(
    List<CharacterCard> additionalCharacters,
    GroupChatRepository groupRepo, {
    String? groupName,
    String? scenario,
    TurnOrder turnOrder = TurnOrder.roundRobin,
    Map<String, ({String text, bool creative})> entrances = const {},
  }) async {
    if (_isGenerating) return null;
    if (_activeCharacter == null || _characterRepository == null) return null;
    if (_messages.isEmpty) return null;
    // 1:1 → group only. Forking from an existing group would rebuild a group
    // from just the active speaker (dropping the other members), so refuse it —
    // use "Add Character to Group" for an existing group instead.
    if (_activeGroup != null) return null;

    final originalCharId = _getCharacterIdFromCard(_activeCharacter!);

    // Build a default group name
    final name = groupName?.isNotEmpty == true
        ? groupName!
        : [
            _activeCharacter!.name,
            ...additionalCharacters.map((c) => c.name),
          ].join(' & ');

    // Create the group
    final group = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      // characterIds removed (decoupled). Members handled via group_members + private storage.
      turnOrder: turnOrder,
      scenario: scenario ?? '',
      // v31 columns — new groups start with clean defaults.
      // baselineRealismState remains '{}' until the caller (or UI) seeds explicit values.
      baselineRealismState: '{}',
    );
    await groupRepo.save(group);

    // Rotation order rule for the new group: original participant(s) first,
    // then arrivals WITH an entrance (in the order added), then arrivals
    // WITHOUT an entrance at the end. Member insertion order *is* the
    // round-robin order (the members table has no explicit sort column), so we
    // insert in exactly that order.
    bool hasEntrance(CharacterCard c) =>
        (entrances[_getCharacterIdFromCard(c)]?.text.trim().isNotEmpty) ?? false;
    final entranceArrivals = additionalCharacters.where(hasEntrance).toList();
    final silentArrivals =
        additionalCharacters.where((c) => !hasEntrance(c)).toList();
    final orderedArrivals = [...entranceArrivals, ...silentArrivals];

    // Decoupled model: ensure members exist for the original 1:1 character
    // and every additional character. Without this, the group loads empty
    // (setActiveGroup / GroupTurnManager will have no one to speak).
    // Ported from the fix originally contributed in PR #44 by @MisterLotto.
    await _createGroupMember(group.id, _activeCharacter!);
    for (final c in orderedArrivals) {
      await _createGroupMember(group.id, c);
    }

    // Create a new session for the group and copy all messages
    final newSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final copiedMessages = <MessagesCompanion>[];
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      // Back-fill characterId on AI messages (null in 1:1 mode)
      String? charId = m.characterId;
      if (!m.isUser && charId == null) {
        charId = originalCharId;
      }
      copiedMessages.add(
        MessagesCompanion(
          sessionId: drift.Value(newSessionId),
          position: drift.Value(i),
          sender: drift.Value(m.sender),
          isUser: drift.Value(m.isUser),
          characterId: drift.Value(charId),
          swipes: drift.Value(jsonEncode(m.swipes)),
          swipeIndex: drift.Value(m.swipeIndex),
          swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
        ),
      );
    }

    // Insert the new session
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: newSessionId,
        groupId: drift.Value(group.id),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_currentSessionId),
        forkIndex: drift.Value(_messages.length - 1),
        trustLevel: drift.Value(_relationshipService.trustLevel),
        activeFixation: drift.Value(_relationshipService.activeFixation),
        fixationLifespan: drift.Value(_relationshipService.fixationLifespan),
        spatialStance: drift.Value(_relationshipService.spatialStance),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (copiedMessages.isNotEmpty) {
      await _db.insertMessages(copiedMessages);
    }

    debugPrint(
      '[ChatService] \u{1F500} Forked 1:1 chat to group "${group.name}" '
      '(${_messages.length} messages copied)',
    );

    // Switch to the new group (this loads the session we just created)
    await setActiveGroup(group, groupRepo: groupRepo);

    // Run any custom entrances WITHOUT blocking the caller, so the wizard can
    // navigate to the group immediately and the entrance messages stream into
    // the now-visible chat instead of waiting behind a spinner. Entrants cut in
    // one-by-one in the order they were added.
    if (entranceArrivals.isNotEmpty) {
      _entrancesInFlight = true; // block user turns until the sequence finishes
      unawaited(() async {
        try {
          for (final addCard in entranceArrivals) {
            final entry = entrances[_getCharacterIdFromCard(addCard)]!;
            final text = entry.text.trim();

            // Members are copied under fresh UUIDs on fork, so resolve by name
            // (stable) and use the resolved member's id — else the entrance
            // attributes to the wrong member.
            final resolved = _groupCharacters.firstWhere(
              (c) => c.name == addCard.name,
              orElse: () => addCard,
            );
            final resolvedId = _getCharacterIdFromCard(resolved);

            if (entry.creative) {
              // Direction: hidden one-shot directive; force this char to speak.
              // Sanitize so the user's text can't break out of the [bracketed]
              // author-note injection or split it across lines.
              final safeText = text
                  .replaceAll(']', ')')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
              _groupManager?.setNextSpeaker(resolved);
              _entranceDirective =
                  'Stage direction (hidden — do NOT quote, repeat, or copy this '
                  'text into the reply): ${resolved.name} enters the scene now, '
                  'following this intent — "$safeText". Write ${resolved.name}\'s '
                  'entrance fresh, in their own voice and words.';
              try {
                await _generateResponse(GenerationMode.normal);
              } catch (e) {
                // Surface the failure so the user isn't left wondering why the
                // group loaded with no entrance.
                debugPrint('[Fork:Entrance] ${resolved.name} failed: $e');
                _entranceDirective = null; // don't leak into a later turn
                _messages.add(
                  ChatMessage(
                    text: '⚠ ${resolved.name}\'s entrance could not be generated.',
                    sender: 'System',
                    isUser: false,
                  ),
                );
                await _saveChat();
                notifyListeners();
              }
            } else {
              // Opening line: the entrance IS the user's text, verbatim — it
              // becomes the character's message as-is, no LLM generation.
              _messages.add(
                ChatMessage(
                  text: text,
                  sender: resolved.name,
                  isUser: false,
                  characterId: resolvedId,
                ),
              );
              await _saveChat();
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('[Fork:Entrance] sequence failed: $e');
        } finally {
          // The entrances are one-off cut-ins. In round-robin the next turn goes
          // to whoever falls right after the LAST entrant in the rotation order
          // (originals, then entrance arrivals, then silent arrivals) — i.e. the
          // first silent arrival, or wrapping back to the original if there are
          // none. advanceAfterRegeneration parks the pointer at last-entrant + 1.
          // Done in `finally` so a generation hiccup can't leave the rotation
          // stuck on the entrant. Random needs no fix-up.
          final lastEntrantName = entranceArrivals.last.name;
          if (turnOrder == TurnOrder.roundRobin &&
              _groupCharacters.any((c) => c.name == lastEntrantName)) {
            final lastEntrant = _groupCharacters.firstWhere(
              (c) => c.name == lastEntrantName,
            );
            _groupManager?.advanceAfterRegeneration(lastEntrant);
          }
          _entrancesInFlight = false; // user turns allowed again
          // The turn pointer changed after generation finished. GroupTurnManager
          // notifies its own listeners, but the chat UI watches ChatService, so
          // we must propagate here — otherwise the next-speaker indicator keeps
          // showing the (stale) entrant even though the pointer is correct.
          notifyListeners();
        }
      }());
    }

    return group;
  }

  /// Create a group member (decoupled model): copy the character's avatar into
  /// the group's private storage and insert a group_members row.
  /// Shared by [addCharacterToGroup] (live add) and [forkToGroupChat] (initial
  /// membership when forking a 1:1 chat into a group).
  ///
  /// This is the core of the fix originally contributed in PR #44 by @MisterLotto.
  Future<void> _createGroupMember(
    String groupId,
    CharacterCard character,
  ) async {
    final mid = const Uuid().v4();
    final avDir = Directory(
      path.join(_storageService.groupsDir.path, groupId, 'avatars'),
    );
    await avDir.create(recursive: true);

    await _characterRepository!.duplicateCharacter(
      character,
      targetDirOverride: avDir.path,
      forcedBasename: mid,
      skipLibraryInsert: true,
    );

    final db = await AppDatabase.instance();
    await db.insertGroupMember(
      GroupMembersCompanion(
        id: drift.Value(mid),
        groupId: drift.Value(groupId),
        name: drift.Value(character.name),
        description: drift.Value(character.description),
        personality: drift.Value(character.personality),
        scenario: drift.Value(character.scenario),
        firstMessage: drift.Value(character.firstMessage),
        mesExample: drift.Value(character.mesExample),
        systemPrompt: drift.Value(character.systemPrompt),
        postHistoryInstructions: drift.Value(character.postHistoryInstructions),
        alternateGreetings: drift.Value(
          jsonEncode(character.alternateGreetings),
        ),
        tags: drift.Value(jsonEncode(character.tags)),
        avatarFilename: drift.Value('$mid.png'),
        ttsVoice: drift.Value(character.ttsVoice),
        lorebook: drift.Value(
          character.lorebook != null
              ? jsonEncode(character.lorebook!.toJson())
              : null,
        ),
        worldNames: drift.Value(jsonEncode(character.worldNames)),
        frontPorchExtensions: drift.Value(
          character.frontPorchExtensions != null
              ? jsonEncode(character.frontPorchExtensions!.toJson())
              : null,
        ),
        rawExtensions: drift.Value(
          character.rawExtensions != null
              ? jsonEncode(character.rawExtensions!)
              : null,
        ),
        memberState: drift.Value('{}'),
      ),
    );
  }

  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;

    // Decoupled model: copy the character's avatar into the group's private
    // storage and insert a group_members row. Shared with forkToGroupChat
    // via _createGroupMember (ported from the fix originally contributed in
    // PR #44 by @MisterLotto).
    await _createGroupMember(_activeGroup!.id, character);

    await groupRepo.save(_activeGroup!);

    // Re-resolve from private members (decoupled).
    final resolved = <CharacterCard>[];
    final memberRows = await groupRepo.getMembersForGroup(_activeGroup!.id);
    for (final m in memberRows) {
      if (m.avatarFilename != null) {
        final p = path.join(
          _storageService.groupsDir.path,
          _activeGroup!.id,
          'avatars',
          m.avatarFilename!,
        );
        if (await File(p).exists()) {
          resolved.add(m.toCharacterCard(resolvedImagePath: p));
        }
      }
    }
    _groupManager?.refreshCharacters(resolved);

    debugPrint(
      '[ChatService] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Remove a character from the currently active group chat.
  /// Returns false if the group would have fewer than 2 characters.
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;
    // Minimum member count now based on loaded group members (decoupled).
    // (enforcement wired via member list length in calling paths)

    // remove ID path removed (decoupled). Real remove deletes the GroupMember row + avatar file.
    final charId = _getCharacterIdFromCard(character);
    // (old removeCharacterId deleted)
    await groupRepo.save(_activeGroup!);

    // Drop any per-char state for the removed member (realism + author notes + per-char system prompts + rag priority)
    _groupRealism.remove(charId);
    _groupAuthorNotes.remove(charId);
    _groupAuthorNoteStrengths.remove(charId);
    _groupCharacterSystemPrompts.remove(charId);
    _groupCharacterRAGPriorities.remove(charId);
    if (_activeGroup != null) {
      // (old checkpoint call removed in v30)
    }

    // Re-resolve after remove — old IDs path removed (decoupled).
    final resolved = <CharacterCard>[]; // from group members
    _groupManager?.refreshCharacters(resolved);

    debugPrint(
      '[ChatService] \u{2796} Removed ${character.name} from group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Returns a stable ID string for a character card.
  /// Delegates to the canonical stable ID for group contexts.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  String _getCharacterId() {
    if (_activeGroup != null) {
      return 'group_${_activeGroup!.id}';
    }
    if (_activeCharacter == null) return "unknown";
    return _getCharacterIdFromCard(_activeCharacter!);
  }

  /// Helper used when constructing messages.
  String? _getCharacterIdForCard(CharacterCard card) {
    return _getCharacterIdFromCard(card);
  }

  /// Safely parse a JSON string into a mutable `Map<String, String>`.
  /// Returns an empty map if [json] is null, empty, or invalid.
  Map<String, String> _tryParseJsonMap(String? json) {
    if (json == null || json.isEmpty || json == '{}') return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return {};
  }

  // v30: Load per-character group realism/needs state.
  // Priority:
  // 1. Live state from the current session's group_realism_state column (if present and non-empty).
  // 2. Default state from the group's default_member_realism_state (important for Group Card imports and new sessions).
  //
  // Pass null for `session` to force-load from group defaults only (used for brand-new group chats).
  void _loadGroupRealismStateFromSession(Session? session) {
    if (_activeGroup == null) return;

    String? stateJson = session?.groupRealismState;

    // Fall back to group definition defaults (crucial for imported Group Cards and split-to-solo)
    if (stateJson == null || stateJson.isEmpty || stateJson == '{}') {
      stateJson = _activeGroup!.defaultMemberRealismState;
    }

    _groupRealism = {};
    _groupDecayRates = {};
    _groupAuthorNotes = {};
    _groupAuthorNoteStrengths = {};
    _groupCharacterSystemPrompts = {};
    _groupCharacterRAGPriorities = {};

    if (stateJson.isNotEmpty && stateJson != '{}') {
      try {
        final decoded = jsonDecode(stateJson);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);

          // Main per-character realism data (needs, emotion, bond, trust, fixation, relationships, arousal, etc.)
          final perChar =
              map['perChar'] ??
              map; // support both wrapped and direct formats during transition
          if (perChar is Map) {
            _groupRealism = perChar.map(
              (k, v) =>
                  MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
            );
          }

          // Global group decay rates
          final globalDecay = map['globalDecayRates'];
          if (globalDecay is Map) {
            _groupDecayRates = globalDecay.map(
              (k, v) => MapEntry(k.toString(), (v as num).toInt()),
            );
          }

          // Per-char author notes (scoped to this group)
          final notes = map['authorNotes'];
          if (notes is Map) {
            _groupAuthorNotes = notes.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          final strengths = map['authorNoteStrengths'];
          if (strengths is Map) {
            _groupAuthorNoteStrengths = strengths.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as num?)?.toInt() ?? _authorNoteStrength,
              ),
            );
          }

          final sysPrompts = map['characterSystemPrompts'];
          if (sysPrompts is Map) {
            _groupCharacterSystemPrompts = sysPrompts.map(
              (k, v) => MapEntry(k.toString(), (v ?? '').toString()),
            );
          }

          // RAG settings (now also in the column)
          if (map.containsKey('ragEnabled')) {
            _groupRagEnabled = map['ragEnabled'] as bool? ?? true;
          }
          if (map.containsKey('retrievalCount')) {
            _groupRetrievalCount =
                (map['retrievalCount'] as num?)?.toInt() ?? 8;
          }
          if (map.containsKey('memoryBudgetPercent')) {
            _groupMemoryBudgetPercent =
                (map['memoryBudgetPercent'] as num?)?.toDouble() ?? 10.0;
          }

          final ragPrios = map['characterRAGPriorities'];
          if (ragPrios is Map) {
            _groupCharacterRAGPriorities = ragPrios.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            );
          }

          // Per-char objectives for group mode (each member has independent tasks)
          _groupObjectives.clear();
          final objMap = map['objectives'];
          if (objMap is Map) {
            objMap.forEach((charId, list) {
              if (list is List) {
                _groupObjectives[charId.toString()] = [];
              }
            });
          }

          // One-time seeding of objectives from an imported Group Card is handled
          // asynchronously after this state load completes (see callers of this method).

          debugPrint(
            '[GroupState v30] Loaded realism state for ${_groupRealism.length} characters '
            '(session + group defaults) for group ${_activeGroup!.name}',
          );
        }
      } catch (e) {
        debugPrint(
          '[GroupState v30] Failed to parse group realism state JSON: $e',
        );
        _groupRealism = {};
      }
    }
  }

  Future<void> _saveChat() async {
    _saveChain = _saveChain.then((_) => _doSaveChat());
    await _saveChain;
  }

  Future<void> _doSaveChat() async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null) {
      return;
    }

    // ── Safety guard: never overwrite existing session data with empty messages.
    // This prevents data loss if _messages is momentarily empty due to a rebuild
    // race, nav glitch, or any other transient state issue.
    if (_messages.isEmpty) {
      debugPrint(
        '[ChatService] ⚠ _saveChat called with empty messages for '
        'session $_currentSessionId — skipping to protect existing data.',
      );
      return;
    }

    // v30: For group chats, serialize current per-character realism state into the
    // new group_realism_state column (clean replacement for hidden checkpoint).
    String groupRealismJson = '{}';
    if (_activeGroup != null) {
      // Include per-char objectives so each group member carries independent tasks.
      final perCharObjectives = <String, List<Map<String, dynamic>>>{};
      _groupObjectives.forEach((charId, list) {
        perCharObjectives[charId] = list
            .map(
              (o) => {
                'id': o.id,
                'objective': o.objective,
                'isPrimary': o.isPrimary,
                'active': o.active,
                // tasks and other fields are stored in the objectives table; we keep lightweight here
              },
            )
            .toList();
      });

      groupRealismJson = jsonEncode({
        'globalDecayRates': _groupDecayRates,
        'perChar': _groupRealism,
        'authorNotes': _groupAuthorNotes,
        'authorNoteStrengths': _groupAuthorNoteStrengths,
        'characterSystemPrompts': _groupCharacterSystemPrompts,
        'ragEnabled': _groupRagEnabled,
        'retrievalCount': _groupRetrievalCount,
        'memoryBudgetPercent': _groupMemoryBudgetPercent,
        'characterRAGPriorities': _groupCharacterRAGPriorities,
        'objectives': perCharObjectives,
        'savedAt': DateTime.now().toIso8601String(),
      });
    }

    // Snapshot messages at the start so async gaps can't see a mutated list.
    final snapshot = List<ChatMessage>.from(_messages);

    // Look up character DB id if in 1:1 mode
    String? characterDbId;
    String? groupDbId;
    if (_activeGroup != null) {
      groupDbId = _activeGroup!.id;
    } else if (_activeCharacter?.dbId != null) {
      characterDbId = _activeCharacter!.dbId;
    }

    // Upsert session (INSERT OR REPLACE to avoid UNIQUE constraint errors)
    final timestamp = int.tryParse(_currentSessionId!) ?? 0;
    final createdAt = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: _currentSessionId!,
        characterId: drift.Value(characterDbId),
        groupId: drift.Value(groupDbId),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        userPersonaId: drift.Value(_userPersonaService.persona.id),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_parentSessionId),
        forkIndex: drift.Value(_forkIndex),
        affectionScore: drift.Value(_relationshipService.affectionScore),
        relationshipTier: drift.Value(_relationshipService.relationshipTier),
        longTermScore: drift.Value(_relationshipService.longTermScore),
        longTermTier: drift.Value(_relationshipService.longTermTier),
        turnsSinceLongTermCheck: drift.Value(
          _relationshipService.turnsSinceLongTermCheck,
        ),
        shortTermDeltasSummary: drift.Value(
          _relationshipService.shortTermDeltasSummary,
        ),
        realismEnabled: drift.Value(_realismEnabled),
        moodDecayCounter: drift.Value(_moodDecayCounter),
        characterEmotion: drift.Value(_characterEmotion),
        emotionIntensity: drift.Value(_emotionIntensity),
        timeOfDay: drift.Value(_timeService.timeOfDay),
        dayCount: drift.Value(_timeService.dayCount),
        startDayOfWeek: drift.Value(_timeService.startDayOfWeekAnchor),
        passageOfTimeEnabled: drift.Value(_timeService.passageOfTimeEnabled),
        nsfwCooldownEnabled: drift.Value(_nsfwService.nsfwCooldownEnabled),
        needsSimEnabled: drift.Value(_needsSimEnabled),
        needsVector: drift.Value(
          _needsSimEnabled ? jsonEncode(_needsSimulation.vector) : null,
        ),
        groupRealismState: drift.Value(groupRealismJson),
        arousalLevel: drift.Value(_nsfwService.arousalLevel),
        cooldownTurnsRemaining: drift.Value(
          _nsfwService.cooldownTurnsRemaining,
        ),
        trustLevel: drift.Value(_relationshipService.trustLevel),
        activeFixation: drift.Value(_relationshipService.activeFixation),
        fixationLifespan: drift.Value(_relationshipService.fixationLifespan),
        spatialStance: drift.Value(_relationshipService.spatialStance),
        chaosModeEnabled: drift.Value(_chaosModeService.chaosModeEnabled),
        chaosPressure: drift.Value(_chaosModeService.chaosPressure),
        trustRepairPending: drift.Value(
          _relationshipService.pendingTrustRepair,
        ),
        createdAt: drift.Value(createdAt),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Per-session generation overrides (v22) — saved via raw SQL so this
    // works even before build_runner regenerates database.g.dart.
    await _db.customUpdate(
      'UPDATE sessions SET generation_settings = ? WHERE id = ?',
      variables: [
        drift.Variable(_sessionGenSettings.toJsonString()),
        drift.Variable(_currentSessionId!),
      ],
      updates: {_db.sessions},
    );

    // Replace all messages for this session using the snapshot.
    // Use a transaction for the delete+insert to keep the replace atomic even
    // if other writers (cloud sync, external tools) touch the DB concurrently.
    await _db.transaction(() async {
      await _db.deleteMessagesForSession(_currentSessionId!);
      final messageBatch = <MessagesCompanion>[];
      for (int i = 0; i < snapshot.length; i++) {
        final m = snapshot[i];
        messageBatch.add(
          MessagesCompanion(
            sessionId: drift.Value(_currentSessionId!),
            position: drift.Value(i),
            sender: drift.Value(m.sender),
            isUser: drift.Value(m.isUser),
            characterId: drift.Value(m.characterId),
            swipes: drift.Value(jsonEncode(m.swipes)),
            swipeIndex: drift.Value(m.swipeIndex),
            swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
            metadata: drift.Value(
              m.metadata != null ? jsonEncode(m.metadata) : null,
            ),
            swipeMetadata: drift.Value(
              m.swipeMetadata.any((e) => e != null)
                  ? jsonEncode(m.swipeMetadata)
                  : null,
            ),
          ),
        );
      }
      if (messageBatch.isNotEmpty) {
        await _db.insertMessages(messageBatch);
      }
    });
  }

  Future<void> _loadLastSession() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    // Get sessions from DB
    List<Session> sessions;
    if (_activeGroup != null) {
      sessions = await _db.getSessionsForGroup(_activeGroup!.id);
    } else if (_activeCharacter?.dbId != null) {
      sessions = await _db.getSessionsForCharacter(_activeCharacter!.dbId!);
    } else {
      return;
    }

    if (sessions.isEmpty) {
      debugPrint('[ChatService] _loadLastSession: No previous sessions found');
      // Ensure no stale fork/parent state remains from a prior character/group.
      _parentSessionId = null;
      _forkIndex = null;
      // Expression runtime (manual/caches) reset on no-prior-session to prevent bleed (new for step4, matches fork/parent hygiene).
      _expressionService.resetForFreshChat();
      // Time (secondary config: passage, weekday anchors, turns, day/time scalars) reset for fresh 0-session/new-group paths.
      // Prevents bleed of advanced time from prior 1:1 into fresh groups (cross-check vs needs bugfix reset hygiene).
      // Nsfw (cooldown/arousal) reset for same (incomplete zeroing of nsfw on 0-session/new-group was a prior hygiene issue).
      // Lorebook triggers/depth reset for same (incomplete zeroing of lore on 0-session/new-group was a prior hygiene pattern to avoid).
      // See "keep reset blocks in sync" (setActiveGroup, startNewChat 1:1+group (now explicit in both), load* , setActive* all must hit this; now includes needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " ; now complete in all group/0-session/new-chat hygiene)" ; incomplete zeroing now complete).
      // (cross-ref setActiveCharacter:1572)
      _timeService.resetForFreshChat();
      _nsfwService.resetForFreshChat();
      _lorebookScanner.resetLorebookTriggerState();
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion =
          false; // zero in _loadLast empty early return (0-session path hygiene)
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadLast empty early return 0-session)
      _isSummaryGenerating =
          false; // secondary zero in _loadLast empty (0-session for summary flag)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero in _loadLast empty early return (0-session path hygiene; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero in _loadLast empty early return (0-session path hygiene; evolution_service (stateless or prompt-only; no reset calls needed))
      return;
    }

    // Sessions are already sorted descending by createdAt
    final lastSession = sessions.first;
    _currentSessionId = lastSession.id;
    _authorNote = lastSession.authorNote;
    _authorNoteStrength = lastSession.authorNoteDepth;
    _summary = lastSession.summary ?? '';
    _summaryLastIndex = lastSession.summaryLastIndex ?? 0;
    _sessionName = lastSession.name;
    _sessionDescription = lastSession.description;
    _parentSessionId = lastSession.parentSession;
    _forkIndex = lastSession.forkIndex;
    // Relationship scalars + migration/tier calc now via service (keeps load parity).
    // Migration: scale old scores (±150) to new range (±300). (Card-seed bypass: fresh V2.5
    // ext seeds use seedFromCardV2OrExt plain clamp in setActiveCharacter/startNew 1:1 paths;
    // this migrate path is *only* for legacy persisted sessions. See card-seed notes at the two
    // ext-seed sites + relationship_service + full keep-sync lists + setActiveCharacter:1572.)
    _relationshipService.loadScalars(
      affectionScore: _relationshipService.migrateShortTermScore(
        lastSession.affectionScore,
      ),
      longTermScore: _relationshipService.migrateLongTermScore(
        lastSession.longTermScore,
      ),
      trustLevel: lastSession.trustLevel,
      activeFixation: lastSession.activeFixation,
      fixationLifespan: lastSession.fixationLifespan,
      spatialStance: lastSession.spatialStance,
      trustRepairPending: lastSession.trustRepairPending,
      turnsSinceLongTermCheck: lastSession.turnsSinceLongTermCheck,
      shortTermDeltasSummary: lastSession.shortTermDeltasSummary,
    );
    // Apply legacy migration (if needed) after load. (Card-seed bypass note: this *10 + migrate
    // path is exclusively for legacy persisted sessions from pre-±300 era; fresh card seeds use
    // the plain seedFromCardV2OrExt at the two 1:1 ext sites above. Expanded per "related load/reset
    // sites" requirement + keep-sync full list + setActiveCharacter:1572 + both startNew.)
    _relationshipService.applyLegacyShortTermMigrationIfNeeded();
    _realismEnabled = lastSession.realismEnabled;
    _moodDecayCounter = lastSession.moodDecayCounter;
    _characterEmotion = lastSession.characterEmotion;
    _emotionIntensity = lastSession.emotionIntensity;
    // Time load via extracted service (resolve + scalars; keeps load blocks in sync).
    _timeService.loadTimeScalars(
      timeOfDay: lastSession.timeOfDay,
      dayCount: lastSession.dayCount,
      startDayOfWeek: lastSession.startDayOfWeek,
      passageOfTimeEnabled:
          lastSession.passageOfTimeEnabled &&
          _storageService.realismSettings.passageOfTimeDefault,
    );
    _nsfwService.loadNsfwScalars(
      nsfwCooldownEnabled: lastSession.nsfwCooldownEnabled,
      arousalLevel: lastSession.arousalLevel,
      cooldownTurnsRemaining: lastSession.cooldownTurnsRemaining,
    );
    _needsSimEnabled = lastSession.needsSimEnabled;
    if (_needsSimEnabled) {
      _needsSimulation.initializeFresh();
      final nv = lastSession.needsVector;
      _needsSimulation.restoreFromSnapshot({
        'vector': (nv is String && nv.isNotEmpty)
            ? (jsonDecode(nv) as Map).cast<String, int>()
            : <String, int>{},
      });
    } else {
      _needsSimulation.clearVector();
    }

    // Re-sync from the character's current setting so that toggling
    // "Enjoys low hygiene" on the character affects existing chats on next load.
    _enjoysLowHygiene =
        _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

    _needsSimulation.resetBuffers();
    // trust/fixation/spatial/pending/affection/tiers already loaded via _relationshipService.loadScalars above.
    debugPrint(
      '[ChatService] _loadLastSession: Loaded session with arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    _chaosModeService.loadScalars(
      modeEnabled: lastSession.chaosModeEnabled,
      pressure: lastSession.chaosPressure,
    );

    // Realism Engine 2.0 Compatibility Migration (delegated to service). (Card-seed bypass:
    // this legacy path for old persisted data; fresh 1:1 card ext seeds use seedFromCardV2OrExt
    // (plain) at setActive/startNew 1:1 sites. See expanded keep-sync + setActiveCharacter:1572.)
    _relationshipService.applyLegacyShortTermMigrationIfNeeded();
    if (_relationshipService.affectionScore != lastSession.affectionScore ||
        _relationshipService.relationshipTier != lastSession.relationshipTier) {
      debugPrint(
        '[Realism] Legacy session migrated to REv2 scales (loadLast).',
      );
    }

    // v30: Load live per-character group realism/needs (bond/trust/emotion/fixation/arousal/relationships/needs)
    // from the session column (or fall back to group defaults). Must happen for group entry paths
    // so that _groupRealism is populated before any eval, prompt injection, or UI read.
    if (_activeGroup != null) {
      _loadGroupRealismStateFromSession(lastSession);
    }

    // Load per-session evolution (1:1 mode only — group is handled by _loadGroupEvolvedFields)
    if (_activeCharacter != null) {
      final charId = _getCharacterIdFromCard(_activeCharacter!);
      _evolvedPersonalities[charId] = lastSession.evolvedPersonality;
      _evolvedScenarios[charId] = lastSession.evolvedScenario;
      _characterEvolutionCount = lastSession.evolutionCount;
      _groupEvolutionCounts[charId] = lastSession.evolutionCount;
    }

    // Load messages
    // Zero secondary objective flags in loaded path of _loadLast (before callers do _loadActiveObjectives / _loadObjectivesForCurrentSpeaker); incomplete zeroing hygiene.
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion = false;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; _loadLast empty/loaded hygiene)
    _isSummaryGenerating =
        false; // secondary flag zero for summary_service (stateless/prompt-only; incomplete zeroing ... now complete)
    _userMessagesSinceLastPeriodicEval = 0;
    _isExtractingFacts =
        false; // secondary fact flag + counter zero in _loadLast loaded path (incomplete zeroing ... now complete; fact_extraction)
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError =
        ''; // explicit evo flag/status/error zero in _loadLast loaded path (incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed))
    try {
      final dbMessages = await _db.getMessagesForSession(_currentSessionId!);
      debugPrint(
        '[ChatService] 🟢 _loadLastSession: loading ${dbMessages.length} '
        'messages for session $_currentSessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        final safeSwipeIndex =
            (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
            ? m.swipeIndex
            : 0;

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: safeSwipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      if (_messages.isNotEmpty) {
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
    } catch (e) {
      print('Error loading chat session: $e');
    }
  }

  /// Get sessions for a given character/group ID without setting it as active.
  Future<List<Map<String, dynamic>>> getSessionsForId(String charId) async {
    // Determine if this is a group or character
    List<Session> dbSessions;
    if (charId.startsWith('group_')) {
      final groupId = charId.replaceFirst('group_', '');
      dbSessions = await _db.getSessionsForGroup(groupId);
    } else {
      // Find character by imagePath basename
      final allChars = await _db.getAllCharacters();
      final match = allChars.where((c) {
        if (c.imagePath == null) return false;
        return path.basenameWithoutExtension(c.imagePath!) == charId;
      }).firstOrNull;
      if (match != null) {
        dbSessions = await _db.getSessionsForCharacter(match.id);
      } else {
        dbSessions = [];
      }
    }

    List<Map<String, dynamic>> sessions = [];
    for (final s in dbSessions) {
      final timestamp = int.tryParse(s.id) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Get message count and preview
      final msgs = await _db.getMessagesForSession(s.id);
      String preview = 'New Conversation';
      if (s.name != null && s.name!.isNotEmpty) {
        preview = s.name!;
      } else if (msgs.length > 1) {
        // Use second message text as preview
        try {
          final swipes = List<String>.from(jsonDecode(msgs[1].swipes));
          preview = swipes.isNotEmpty ? swipes[msgs[1].swipeIndex] : '';
          if (preview.length > 50) preview = '${preview.substring(0, 50)}...';
        } catch (_) {}
      }

      sessions.add({
        'id': s.id,
        'date': date,
        'preview': preview,
        'message_count': msgs.length,
        'user_message_count': msgs.where((m) => m.isUser).length,
        if (s.name != null) 'session_name': s.name,
        if (s.description != null) 'session_description': s.description,
        if (s.parentSession != null) 'parent_session': s.parentSession,
        if (s.forkIndex != null) 'fork_index': s.forkIndex,
      });
    }

    sessions.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );
    return sessions;
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    if (_activeCharacter == null && _activeGroup == null) return [];
    final charId = _getCharacterId();
    return getSessionsForId(charId);
  }

  Future<void> loadSession(String sessionId) async {
    if (_activeCharacter == null && _activeGroup == null) return;

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    if (session.userPersonaId != null) {
      await _userPersonaService.setActivePersona(session.userPersonaId!);
    }

    try {
      final dbMessages = await _db.getMessagesForSession(sessionId);
      debugPrint(
        '[ChatService] 🟢 loadSession: loading ${dbMessages.length} '
        'messages for session $sessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        final safeSwipeIndex =
            (m.swipeIndex >= 0 && m.swipeIndex < swipes.length)
            ? m.swipeIndex
            : 0;

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[safeSwipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: safeSwipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      // Post-load sanitization: force valid swipe indices and clamp absurdly long fixation text.
      // This protects against any legacy corrupted rows or previous buggy saves, even if the
      // individual message constructors already clamp.
      for (final msg in _messages) {
        if (msg.swipeIndex < 0 || msg.swipeIndex >= msg.swipes.length) {
          msg.swipeIndex = 0;
        }
      }

      // The fixation coming out of the LLM can sometimes be a full paragraph instead of a short topic.
      // Truncate it to keep the UI and prompts sane.
      _relationshipService.sanitizeFixationIfTooLong();

      // ── Hydrate hidden group state checkpoint (DB-free: realism + per-char notes) ──
      // The sentinel is stored as the last message for durability but must be
      // stripped from the in-memory list so the UI and prompt builders never see it.
      // (v30: _hydrateGroupRealismCheckpointIfPresent removed — state now loads from DB column)

      _currentSessionId = sessionId;
      _authorNote = session.authorNote;
      _authorNoteStrength = session.authorNoteDepth;
      _summary = session.summary ?? '';
      _summaryLastIndex = session.summaryLastIndex ?? 0;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused on loadSession loaded path (incomplete zeroing ... now complete; see keep-sync + summary_service)
      _isSummaryGenerating =
          false; // secondary zero for flag on loadSession loaded (symmetric)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero on loadSession loaded (symmetric; incomplete zeroing ... now complete; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero on loadSession loaded (symmetric; incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed))
      _sessionName = session.name;
      _sessionDescription = session.description;
      _parentSessionId = session.parentSession;
      _forkIndex = session.forkIndex;
      // Relationship load + tier calc + legacy migration via service.
      _relationshipService.loadScalars(
        affectionScore: session.affectionScore,
        longTermScore: session.longTermScore,
        trustLevel: session.trustLevel,
        activeFixation: session.activeFixation,
        fixationLifespan: session.fixationLifespan,
        spatialStance: session.spatialStance,
        trustRepairPending: session.trustRepairPending,
        turnsSinceLongTermCheck: session.turnsSinceLongTermCheck,
        shortTermDeltasSummary: session.shortTermDeltasSummary,
      );
      _relationshipService.applyLegacyShortTermMigrationIfNeeded();
      // (Card-seed bypass: legacy *10 migration only; see the two ext-seed sites + prior load sites
      // for full "card seeds authored on current ±300" + keep-sync lists + relationship leaf.)

      // counters already via loadScalars on service.
      _realismEnabled = session.realismEnabled;
      _moodDecayCounter = session.moodDecayCounter;
      _characterEmotion = session.characterEmotion;
      _emotionIntensity = session.emotionIntensity;
      // Time load via extracted service (resolve + scalars; keeps group load blocks in sync).
      _timeService.loadTimeScalars(
        timeOfDay: session.timeOfDay,
        dayCount: session.dayCount,
        startDayOfWeek: session.startDayOfWeek,
        passageOfTimeEnabled:
            session.passageOfTimeEnabled &&
            _storageService.realismSettings.passageOfTimeDefault,
      );
      _nsfwService.loadNsfwScalars(
        nsfwCooldownEnabled: session.nsfwCooldownEnabled,
        arousalLevel: session.arousalLevel,
        cooldownTurnsRemaining: session.cooldownTurnsRemaining,
      );
      _needsSimEnabled = session.needsSimEnabled;
      if (_needsSimEnabled) {
        _needsSimulation.initializeFresh();
        final nv = session.needsVector;
        _needsSimulation.restoreFromSnapshot({
          'vector': (nv is String && nv.isNotEmpty)
              ? (jsonDecode(nv) as Map).cast<String, int>()
              : <String, int>{},
        });
      } else {
        _needsSimulation.clearVector();
      }

      // Re-sync from the character's current setting so toggling
      // "Enjoys low hygiene" affects existing chats on load.
      _enjoysLowHygiene =
          _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;

      _needsSimulation.resetBuffers();
      // trust/fixation etc already via _relationshipService.loadScalars above.

      // Load per-session evolution (1:1 mode only — group handled by _loadGroupEvolvedFields)
      if (_activeCharacter != null) {
        final charId = _getCharacterIdFromCard(_activeCharacter!);
        _evolvedPersonalities[charId] = session.evolvedPersonality;
        _evolvedScenarios[charId] = session.evolvedScenario;
        _characterEvolutionCount = session.evolutionCount;
        _groupEvolutionCounts[charId] = session.evolutionCount;
      }

      // Per-session generation parameter overrides (v22) — loaded via raw SQL
      // so this works even before build_runner regenerates database.g.dart.
      try {
        final genRows = await _db
            .customSelect(
              'SELECT generation_settings FROM sessions WHERE id = ?',
              variables: [drift.Variable(sessionId)],
            )
            .get();
        final genJson = genRows.isNotEmpty
            ? genRows.first.read<String?>('generation_settings')
            : null;
        _sessionGenSettings = ChatGenerationSettings.fromJsonString(genJson);
      } catch (_) {
        _sessionGenSettings = ChatGenerationSettings();
      }

      if (_messages.isNotEmpty) {
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
      notifyListeners();
    } catch (e) {
      print('Error loading session $sessionId: $e');
    }
  }

  /// Rename a session.
  Future<void> renameSession(String sessionId, String name) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        name: drift.Value(name.isEmpty ? null : name),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionName = name.isEmpty ? null : name;
      notifyListeners();
    }
  }

  /// Update the description of a session.
  Future<void> updateSessionDescription(
    String sessionId,
    String description,
  ) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        description: drift.Value(description.isEmpty ? null : description),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionDescription = description.isEmpty ? null : description;
      notifyListeners();
    }
  }

  /// Create a new session by forking from message at [messageIndex].
  /// Copies messages 0..messageIndex into a new session and switches to it.
  Future<void> forkFromMessage(int messageIndex) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null) {
      return;
    }
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final oldSessionId = _currentSessionId!;
    final forkedMessages = _messages
        .sublist(0, messageIndex + 1)
        .map(
          (m) => ChatMessage(
            text: m.text,
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: List.from(m.swipes),
            swipeIndex: (m.swipeIndex >= 0 && m.swipeIndex < m.swipes.length)
                ? m.swipeIndex
                : 0,
            swipeDurations: List.from(m.swipeDurations),
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(m.metadata!)
                : null,
            swipeMetadata: m.swipeMetadata
                .map((e) => e != null ? Map<String, dynamic>.from(e) : null)
                .toList(),
          ),
        )
        .toList();

    debugPrint(
      '[ChatService] 🟡 forkSession: clearing messages for fork at index $messageIndex',
    );
    _messages.clear();
    _messages.addAll(forkedMessages);
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _parentSessionId = oldSessionId;
    _forkIndex = messageIndex;
    _sessionGenSettings = _sessionGenSettings
        .copy(); // inherit parent's overrides
    _summary = '';
    _summaryLastIndex = 0;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric to generating; fork hygiene + incomplete zeroing now complete)
    _isSummaryGenerating =
        false; // zero secondary flag on fork (new branch hygiene, matches summary scalar reset)
    _userMessagesSinceLastPeriodicEval = 0;
    _isExtractingFacts =
        false; // secondary fact flag + counter zero on fork (new branch hygiene + incomplete zeroing now complete; fact_extraction)
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError =
        ''; // explicit evo flag/status/error zero on fork (new branch hygiene + incomplete zeroing now complete; evolution_service (stateless or prompt-only; no reset calls needed))

    // Time-Travel Restoration
    if (_messages.isNotEmpty) {
      _restoreRealismStateFromMessage(_messages.last);
    }

    await _saveChat();
    notifyListeners();
  }

  // Import chat from SillyTavern JSON format
  Future<void> importFromSillyTavern(String jsonData) async {
    if (_activeCharacter == null) throw Exception('No active character');

    try {
      final Map<String, dynamic> data = jsonDecode(jsonData);
      final List<dynamic> messages = data['messages'] ?? [];

      debugPrint(
        '[ChatService] 🟡 importFromSillyTavern: clearing messages for import',
      );
      _messages.clear();

      for (final msg in messages) {
        final String name = msg['name'] ?? '';
        final bool isUser = msg['is_user'] ?? false;
        final String text = msg['mes'] ?? '';

        _messages.add(ChatMessage(text: text, sender: name, isUser: isUser));
      }

      // Create new session for imported chat
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to parse SillyTavern JSON: $e');
    }
  }

  // Export current chat to SillyTavern JSON format
  String? exportToSillyTavern() {
    if (_messages.isEmpty) return null;

    final List<Map<String, dynamic>> messages = _messages.map((msg) {
      return {
        'name': msg.sender,
        'is_user': msg.isUser,
        'mes': msg.text,
        'send_date': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();

    final Map<String, dynamic> export = {
      'chat_metadata': {'note_prompt': '', 'note_interval': 0},
      'messages': messages,
    };

    return jsonEncode(export);
  }

  Future<void> startNewChat() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    debugPrint(
      '[startNewChat] START: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );

    // Refresh _activeCharacter from the repository so we pick up any edits
    // made in the character editor (personality, description, etc.)
    if (_activeCharacter != null && _characterRepository != null) {
      final freshChar = _characterRepository!.characters
          .cast<CharacterCard?>()
          .firstWhere(
            (c) => c!.dbId == _activeCharacter!.dbId,
            orElse: () => null,
          );
      if (freshChar != null) {
        // Preserve any runtime-loaded extensions if the repository instance lacks them
        final existingExt = _activeCharacter!.frontPorchExtensions;
        final existingRaw = _activeCharacter!.rawExtensions;

        _activeCharacter = freshChar;

        if (existingExt != null &&
            _activeCharacter!.frontPorchExtensions == null) {
          _activeCharacter!.frontPorchExtensions = existingExt;
          _activeCharacter!.rawExtensions = existingRaw;
          debugPrint(
            '[startNewChat] Preserved existing extensions during character refresh',
          );
        } else if (existingExt == null &&
            _activeCharacter!.frontPorchExtensions == null) {
          debugPrint(
            '[startNewChat] DEBUG: existingExt was null AND freshChar had null extensions.',
          );
        }
      } else {
        debugPrint(
          '[startNewChat] DEBUG: freshChar was null (repository lookup failed).',
        );
      }
    }

    // Fallback: If extensions are STILL missing, forcefully reload from PNG.
    // This catches edge cases where repository/memory loses sync with the file.
    if (_activeCharacter != null &&
        _activeCharacter!.frontPorchExtensions == null) {
      debugPrint(
        '[startNewChat] DEBUG: Extensions are missing. Attempting PNG fallback.',
      );
      if (_activeCharacter!.imagePath != null) {
        debugPrint(
          '[startNewChat] DEBUG: Image path exists: ${_activeCharacter!.imagePath}',
        );
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(
            _activeCharacter!.imagePath!,
          );
          if (reloaded == null) {
            debugPrint(
              '[startNewChat] DEBUG: readCard returned null. Failed to parse PNG.',
            );
          } else if (reloaded.frontPorchExtensions != null) {
            _activeCharacter!.frontPorchExtensions =
                reloaded.frontPorchExtensions;
            _activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint(
              '[startNewChat] Force-reloaded frontPorchExtensions from PNG',
            );
          } else {
            debugPrint(
              '[startNewChat] DEBUG: readCard succeeded, BUT reloaded.frontPorchExtensions was NULL! Meaning the PNG file does NOT contain the front_porch extension data.',
            );
          }
        } catch (e) {
          debugPrint('[startNewChat] Force-reload failed with exception: $e');
        }
      } else {
        debugPrint('[startNewChat] DEBUG: Cannot fallback. imagePath is null.');
      }
    }

    debugPrint(
      '[ChatService] 🟡 startNewChat: clearing messages (had ${_messages.length})',
    );
    _messages.clear();
    _greetingIndex = 0;
    _summary = '';
    _summaryLastIndex = 0;
    _summaryPaused =
        false; // explicit secondary zero for _summaryPaused (symmetric; startNew 1:1/ext-seed branch + incomplete zeroing ... now complete)
    _isSummaryGenerating =
        false; // explicit in startNewChat 1:1/ext-seed branch (both startNew explicit + incomplete zeroing... now complete (see CLAUDE.md); summary_service) + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete in both branches)"

    // Explicitly clear any prior branching/fork metadata. A "New Chat" is
    // never a branch/fork from a previous session. This prevents stale
    // _parentSessionId / _forkIndex (from a previous branched chat or
    // different character) from being written into the brand-new session
    // record via _saveChat(), which was causing new chats to incorrectly
    // show "Branched at message #NNNN" in history lists even for characters
    // with no prior chats.
    _parentSessionId = null;
    _forkIndex = null;

    // Mark this as a new chat to prevent memory retrieval
    _isNewChat = true;
    debugPrint('[startNewChat] Marked as new chat - memories will be filtered');

    // Save the current session (preserves objectives for this session)
    if (_currentSessionId != null) {
      await _saveChat();
    }

    // Clear objectives for fresh session start
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;
    _isCheckingCompletion =
        false; // see decl + keep reset blocks (incomplete zeroing... now complete (see CLAUDE.md); explicit in both startNew branches)
    _userMessagesSinceLastPeriodicEval = 0;
    _isExtractingFacts =
        false; // explicit secondary fact flag + counter zero in startNew 1:1/ext-seed branch (both startNew explicit + incomplete zeroing ... now complete; fact_extraction)
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError =
        ''; // explicit evo flag/status/error zero in startNew 1:1/ext-seed branch (both startNew explicit + incomplete zeroing ... now complete; evolution_service (stateless or prompt-only; no reset calls needed))

    // Create new session ID for the new chat
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Clear memory sources to prevent old memories from being retrieved
    // Cross-character memory can still be re-selected by user after new chat starts
    if (_activeCharacter?.dbId != null) {
      try {
        await _db.updateCharacter(
          CharactersCompanion(
            id: drift.Value(_activeCharacter!.dbId!),
            memorySources: drift.Value('[]'),
          ),
        );
        debugPrint('[startNewChat] Cleared memory sources from DB');
      } catch (e) {
        debugPrint('[startNewChat] Failed to clear memory sources: $e');
      }
    }

    // Seed Realism Engine state from V2.5 card extensions for 1:1 mode only,
    // ensuring realism settings persist across chat sessions (group mode handled elsewhere)
    if (_activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();

      _realismEnabled = extSeed.realismEnabled;
      // Card-seed bypass (rec 1 from PR #47; keeps startNewChat parity with setActive ext seed):
      // use seedFromCardV2OrExt (plain .clamp only, no _migrate*) because V2.5 cards + creator
      // author on current ±300 scale. (The old "Migration + seed" comment + call was the source
      // of the doubling regression on fresh 1:1 New Chat.) Migration stays exclusively on legacy
      // persisted session paths (_loadLastSession + loadScalars(migrate*) + applyLegacy... at 3 sites).
      // 1:1 vs group parity: group seeding paths untouched (resetForFresh + per-speaker load/save scalars).
      // See relationship_service.dart (seedFromCardV2OrExt + public migrate docs) + expanded
      // "keep reset blocks in sync" + "incomplete zeroing... now complete (see CLAUDE.md)"
      // (see CLAUDE.md full list + incomplete zeroing hygiene; buffer removal complete)
      _relationshipService.seedFromCardV2OrExt(
        shortTermBond: extSeed.shortTermBond,
        longTermBond: extSeed.longTermBond,
        trustLevel: extSeed.trustLevel,
      );
      _expressionService.resetForFreshChat();
      // Lorebook trigger reset via extracted service (keeps the keep-sync reset sites correct
      // without god privates; now includes startNewChat 1:1 ext-seed path to prevent bleed of prior
      // isTriggered/remainingDepth into fresh New Chat for 1:1; constants skipped. See setActiveCharacter:1572
      // + "incomplete zeroing of secondary realism configuration fields" briefing pattern (cross-ref step6 nsfw).
      // See lorebook_scanner.dart and "keep reset blocks" comments (now lists needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc; card-seed bypass hygiene added here too)
      _lorebookScanner.resetLorebookTriggerState();
      // Time seed via extracted service (keeps startNewChat / setActive / ext-seed blocks in sync).
      _timeService.seedFromV2OrExt(
        dayCount: extSeed.dayCount.clamp(1, 9999),
        timeOfDay: extSeed.timeOfDay,
        passageOfTimeEnabled:
            extSeed.passageOfTimeEnabled &&
            _storageService.realismSettings.passageOfTimeDefault,
      );
      _characterEmotion = extSeed.characterEmotion;
      _emotionIntensity = extSeed.emotionIntensity;
      _nsfwService.seedFromV2OrExt(
        nsfwCooldownEnabled: extSeed.nsfwCooldownEnabled,
      );
      _chaosModeService.seedFromGroupOrExt(extSeed.chaosModeEnabled, false);
      _needsSimEnabled = extSeed.needsSimEnabled;
      _enjoysLowHygiene = extSeed.enjoysLowHygiene;
      if (_needsSimEnabled) {
        // Fresh chat / new session: seed from card baselines (falls back to
        // needDefaults when the card has no baselines).
        _needsSimulation.initializeFreshWithDefaults({
          'hunger': extSeed.needsBaselineHunger,
          'bladder': extSeed.needsBaselineBladder,
          'energy': extSeed.needsBaselineEnergy,
          'social': extSeed.needsBaselineSocial,
          'fun': extSeed.needsBaselineFun,
          'hygiene': extSeed.needsBaselineHygiene,
          'comfort': extSeed.needsBaselineComfort,
        });
      } else {
        _needsSimulation.clearVector();
      }
      _needsSimulation.resetBuffers();
      // needs_impact_evaluator is stateless/prompt-only (no reset calls needed on it;
      // see full list in "keep reset blocks in sync" comments + cross-ref setActiveCharacter:1572 + fact_extraction (stateless or prompt-only; no reset calls needed) + evolution_service (stateless or prompt-only; no reset calls needed) + realism_verification (stateless or prompt-only; no reset calls needed) + " ; read live from ext on active/group speaker; incomplete zeroing... now complete (see CLAUDE.md) (no extra scalar)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)".

      // pending covered by relationship service reset in the ext-seed or non-ext paths below.
      // Always reset per-chat runtime realism fields (arousal/fixation/cooldowns) for a fresh
      // session started via explicit New Chat. ... (See also: matching full reset in setActiveCharacter
      // and the cross-sync comment there; load*Session, deleteSession→startNewChat, setActiveGroup defensive zero.
      // Needs vector/buffers reset via _needsSimulation also kept in sync across sites.)
      // Time secondary fields (passage/anchor/turns/day/time) zeroed via _timeService.resetForFreshChat in non-ext path + _load empty + setActiveGroup.
      // Nsfw runtime (arousal/cooldown) zeroed via service for fresh (see resetRuntime + resetForFreshChat).
      // Declarative initial bond/trust/emotion/day etc are already seeded above from the card's
      // FrontPorchExtensions (or defaults). The old hasFrontPorchExtensions preserve here
      // was the source of fixation bleed on "New Chat" for cards that had any FP ext object.
      // Expression (manual/caches/onnx/lastAvatar) reset via service for no-bleed (new for step 4).
      // Lorebook (non-const isTriggered/remainingDepth) reset via scanner in both ext-seed (1:1) and non-ext (group/0-session) paths of startNewChat (added for hygiene to match briefing "every keep-sync" + setActiveCharacter etc; prevents bleed into greetings/scans).
      debugPrint(
        '[startNewChat] Resetting runtime arousal/fixation + transients for fresh chat (was: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan})',
      );
      _nsfwService.resetRuntimeArousalAndCooldown();
      debugPrint(
        '[startNewChat] After reset: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
      );

      // Recalculate tiers from seeded scores (only needed for realism-enabled chars)
      if (_realismEnabled) {
        // Tiers are maintained inside service after seed; no direct _calculate here.
      }

      // Seed initial quest/task as a primary objective
      if (extSeed.currentTask.isNotEmpty) {
        // Defer so the session ID is ready before the DB write
        Future.microtask(() async {
          await setObjective(extSeed.currentTask, isPrimary: true);
          debugPrint(
            '[ChatService] V2.5 seeded initial task: ${extSeed.currentTask}',
          );
        });
      }
    } else {
      // Group mode or no active character: reset to defaults but preserve existing extensions-based values
      // (pending covered by service.resetForFreshChat below)

      if (_activeGroup == null && _messages.isNotEmpty) {
        // Will be populated later with greeting in non-group modes
        // Preserve realism state for proper post-greeting eval (don't reset here)
      } else {
        // Relationship + Expression + Time + Nsfw reset via service helpers (keeps reset blocks in sync with setActiveCharacter:1572 etc / _loadLast empty / setActiveGroup / startNew ext-seed; see "incomplete zeroing... now complete (see CLAUDE.md)" + full list in "keep reset blocks" comments including + llm_eval_engine (stateless or prompt-only; no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed)). (cross-ref setActiveCharacter:1572 etc)
        // Time now explicitly reset in group 0-session/empty paths + setActiveGroup defensive + _loadLast empty (cross-check needs bugfix hygiene).
        _relationshipService.resetForFreshChat();
        _expressionService.resetForFreshChat();
        _timeService.resetForFreshChat();
        _nsfwService.resetForFreshChat();
        // Lorebook trigger reset via extracted service (keeps reset blocks in sync with setActiveCharacter:1572 / _loadLast empty / setActiveGroup / startNew ext-seed; see "incomplete zeroing of secondary ... on 0-session/new-character/group" + startNew 1:1+group now complete + full list in keep-sync comments incl llm_eval_engine). (cross-ref setActiveCharacter:1572 etc)
        // See "keep reset blocks in sync" comments (setActiveGroup, startNewChat, load* , setActive* all must hit this; now includes needs/chaos/... + leaves (see CLAUDE.md for full; incomplete zeroing now complete) + " )" for group/0-session/new-chat hygiene; incomplete zeroing now complete).
        // (cross-ref setActiveCharacter:1572)
        _lorebookScanner.resetLorebookTriggerState();
        // Don't touch dayCount/time etc directly — seeded from extensions or loaded session (or reset above for fresh no-ext path).
        // Time reset helper kept in sync with other blocks.
        // needs_impact_evaluator (stateless/prompt-only; no reset calls needed) covered in keep-sync lists.

        // Explicit zero for secondary config flags in group/non-ext/0-session/new-chat path (keeps "incomplete zeroing... now complete (see CLAUDE.md)" true in *code* not just comments; matches ext-seed 1:1 + setActiveCharacter + setActiveGroup defensive; cross-ref setActiveCharacter:1572 + full list in keep-sync comments incl + needs_impact_evaluator (stateless or prompt-only; no reset calls needed) + realism_evals (stateless or prompt-only; no reset calls needed) + " ; authority mode for needs; hygiene listed, no code zero line)") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)".
        _needsSimEnabled = false;
        _enjoysLowHygiene = false;
        _needsSimulation.clearVector();
        _needsSimulation.resetBuffers();
        _activeObjectives = [];
        _messagesSinceLastCheck = 0;
        _isCheckingCompletion =
            false; // explicit in non-ext/group/0-session else branch of startNew (both branches now; incomplete zeroing ... now complete)
        _summaryPaused =
            false; // explicit secondary zero for _summaryPaused (symmetric to generating; non-ext/group/0-session startNew path + now complete)
        _isSummaryGenerating =
            false; // explicit secondary zero in startNew non-ext/group/0-session path (both branches + now complete for summary flag too)
        _userMessagesSinceLastPeriodicEval = 0;
        _isExtractingFacts =
            false; // explicit secondary fact flag + counter zero in startNew non-ext/group/0-session path (both branches + now complete for fact flag/counter; fact_extraction)
        _isEvolvingCharacter = false;
        _evolutionStatus = '';
        _evolutionError =
            ''; // explicit evo flag/status/error zero in startNew non-ext/group/0-session path (both branches + now complete for evo flag; evolution_service (stateless or prompt-only; no reset calls needed) + " )") + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)"
      }
    }

    // Explicit flag zero for evolution (in addition to per-branch) to keep "incomplete zeroing... now complete (see CLAUDE.md)" + both startNew explicit; evolution_service (stateless or prompt-only; no reset calls needed) + " ; no god scalar zero needed -- live ext read; see also setActiveCharacter + group 0-session paths)" + "needsSimulation. (reason support kept for Director chips) ; cleared via sim initializeFresh/clearVector/resetBuffers on all paths; now complete)".
    _isEvolvingCharacter = false;
    _evolutionStatus = '';
    _evolutionError = '';

    // Clear the in-memory evolution cache so the new session starts with
    // the original (unevolved) personality/scenario. The previous session's
    // evolved data was still live in this map. (Flags zeroed explicitly in branches + here for hygiene; see preceding comment.)
    _evolvedPersonalities.clear();
    _evolvedScenarios.clear();
    _groupEvolutionCounts.clear();
    _characterEvolutionCount = 0;

    if (_activeGroup != null && _groupCharacters.isNotEmpty) {
      // Group mode: respect explicit group.firstMessage (custom group greeting set
      // by creator or Group Card) when present. Only fall back to the first
      // participating character's firstMessage when the group has no custom opening.
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (_activeGroup!.firstMessage.isNotEmpty) {
        greetingText = _applyUserReplacement(_activeGroup!.firstMessage);
        greetingSender = _activeGroup!.name;
        greetingCharId = null;
      } else {
        final first = _groupCharacters.first;
        greetingText = first.firstMessage.isNotEmpty
            ? _buildFirstMessage(first)
            : '';
        greetingSender = first.name;
        greetingCharId = _getCharacterIdFromCard(first);
      }

      if (greetingText.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
      _groupManager?.resetTurnState();
    } else if (_activeCharacter != null) {
      // 1:1 mode
      if (_activeCharacter!.firstMessage.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: _buildFirstMessage(_activeCharacter!),
            sender: _activeCharacter!.name,
            isUser: false,
          ),
        );
        _lorebookScanner.scanLorebook(_messages.last.text);
      }
    }

    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint(
      '[startNewChat] BEFORE SAVE: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    await _saveChat();
    debugPrint(
      '[startNewChat] AFTER SAVE: arousal=${_nsfwService.arousalLevel}, fixation=${_relationshipService.activeFixation}/${_relationshipService.fixationLifespan}',
    );
    notifyListeners();

    // ── Post-Greeting Realism Baseline ──────────────────────────────────
    // Always mark that a greeting was placed — even if Realism is currently off.
    // If Realism is already on, fire immediately. Otherwise the flag will be
    // consumed the moment the user enables Realism.
    // Skip if character already has pre-seeded V2.5 extensions — those baseline
    // values are intentional and should not be overwritten by auto-eval.
    // (See also: setActiveCharacter 0-session path comment for why direct imports rely on retro path.)
    if (_activeGroup == null &&
        _messages.isNotEmpty &&
        _activeCharacter!.frontPorchExtensions == null) {
      _greetingEvalPending = true;
      if (_realismEnabled) {
        _runPostGreetingEval();
      }
    }
  }

  /// Evaluates emotion + relationship baseline from the greeting message only.
  /// Runs once per new session, silently in the background.
  Future<void> _runPostGreetingEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    _greetingEvalPending = false; // consume the pending flag
    debugPrint('[Realism] Running post-greeting baseline eval...');
    _isProcessingGreeting = true;
    notifyListeners();
    try {
      await Future.wait([
        // delegates to _llmEvalEngine (step 9 thins; full bodies excised)
        _evaluateEmotionalStateCall(),
        _evaluateRelationshipCall(),
      ]);

      if (_realismEvalCancelled) {
        debugPrint('[Realism] Post-greeting eval cancelled');
        _realismEvalCancelled = false;
        return;
      }

      // Check for cancellation after each eval
      if (_realismEvalCancelled) {
        debugPrint('[Realism] Post-greeting eval cancelled');
        _realismEvalCancelled =
            false; // Reset the flag so future messages can proceed
        return;
      }

      // Store initial emotion in metadata on the greeting message itself
      if (_messages.isNotEmpty) {
        _messages.first.activeMetadata ??= {};
        if (_characterEmotion.isNotEmpty) {
          _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
          _messages.first.activeMetadata!['realism_state'] =
              _captureRealismState();
        }
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Post-greeting baseline: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
      );
    } catch (e) {
      debugPrint('[Realism] Post-greeting eval failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Retroactive baseline eval — fires when Realism is enabled mid-conversation
  /// with no prior state captured. Evaluates the full visible message history
  /// so the engine catches up on emotion, bond, and scene state.
  Future<void> _runRetroactiveBaselineEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    debugPrint(
      '[Realism] Running retroactive baseline scan (${_messages.length} messages)...',
    );
    _isProcessingGreeting = true; // reuse the greeting overlay
    notifyListeners();
    try {
      if (_storageService.realismSettings.realismOneShotEval) {
        await _evaluateOneShotCall(); // step 10 thin (full in realism_evals)

        // Check for cancellation after one-shot eval
        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          return;
        }
      } else {
        await Future.wait([
          _evaluateRelationshipCall(),
          _evaluateEmotionalStateCall(),
          _evaluatePhysicalStateCall(),
          _evaluateNarrativeCall(),
        ]);

        if (_realismEvalCancelled) {
          debugPrint('[Realism] Retroactive scan cancelled');
          _realismEvalCancelled = false;
          return;
        }
      }

      // Stamp the baseline on the most recent message so it persists
      if (_messages.isNotEmpty) {
        _messages.last.activeMetadata ??= {};
        _messages.last.activeMetadata!['emotion_label'] = _characterEmotion;
        _messages.last.activeMetadata!['realism_state'] =
            _captureRealismState();
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Retroactive scan complete: emotion=$_characterEmotion, bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}',
      );
    } catch (e) {
      debugPrint('[Realism] Retroactive baseline scan failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Cycle the first message through alternate greetings
  Future<void> cycleGreeting(int direction) async {
    if (_activeCharacter == null || _messages.isEmpty) return;
    final allGreetings = _activeCharacter!.allGreetings;
    if (allGreetings.length <= 1) return;

    _greetingIndex = (_greetingIndex + direction) % allGreetings.length;
    if (_greetingIndex < 0) _greetingIndex += allGreetings.length;

    // Replace the first message text
    final greeting = allGreetings[_greetingIndex];
    _messages[0] = ChatMessage(
      text: _buildFirstMessage(_activeCharacter!, greetingText: greeting),
      sender: _activeCharacter!.name,
      isUser: false,
    );

    await _saveChat();
    notifyListeners();

    // Re-run baseline eval for the new greeting (skip pre-seeded V2.5 cards)
    if (_realismActiveThisMode &&
        _activeCharacter!.frontPorchExtensions == null) {
      _runPostGreetingEval();
    }
  }

  String _buildFirstMessage(CharacterCard character, {String? greetingText}) {
    String msg = greetingText ?? character.firstMessage;
    // Use the robust replacement logic from the model
    return character.replacePlaceholders(
      msg,
      userName: _userPersonaService.persona.name,
    );
  }

  /// Applies {{user}} / `<user>` replacement using the current persona.
  /// Used for group-level overrides (firstMessage, scenario, systemPrompt)
  /// which are not tied to a specific CharacterCard.
  String _applyUserReplacement(String text) {
    if (text.isEmpty) return text;
    final userName = _userPersonaService.persona.name;
    return text
        .replaceAll(RegExp(r'\{\{user\}\}', caseSensitive: false), userName)
        .replaceAll(RegExp(r'<user>', caseSensitive: false), userName);
  }

  Future<void> sendMessage(String text) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        text.trim().isEmpty) {
      return;
    }
    // Don't let a user turn start while forked-in entrances are still playing —
    // it would race the one-shot entrance directive / turn positioning.
    if (_entrancesInFlight) return;
    clearSuggestions();

    // ── Slash Command Handling ──────────────────────────────────────────
    final trimmed = text.trim();
    if (trimmed.startsWith('/')) {
      final parts = trimmed.substring(1).split(RegExp(r'\s+'));
      final command = parts.first.toLowerCase();
      final args = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      switch (command) {
        case 'expression-set':
        case 'expression':
          if (args.isNotEmpty) {
            final label = args.toLowerCase();
            _expressionService.setManualExpression(label);
          } else {
            _expressionService.setManualExpression(null);
          }
          return;

        case 'expression-clear':
          _expressionService.setManualExpression(null);
          return;

        default:
          // Unknown command — proceed as normal message
          break;
      }
    }

    // In observer mode, route to sendDirectorNote instead
    if (_observerMode && _activeGroup != null) {
      await sendDirectorNote(text);
      return;
    }

    final senderName = _userPersonaService.persona.name;
    _messages.add(ChatMessage(text: text, sender: senderName, isUser: true));
    await _saveChat();
    notifyListeners();

    // Clear the new chat flag after first user message to allow memory retrieval
    if (_isNewChat) {
      _isNewChat = false;
      debugPrint('[sendMessage] Cleared new chat flag, memories now allowed');
    }

    // Scan user input for lore keywords (thin to scanner).
    _lorebookScanner.scanLorebook(text);

    // ── Clear consumed chaos event from the previous turn ───────────────
    // Only clear if the event was already delivered in a response.
    // This preserves manual-spin events that haven't been used yet.
    // Delegated to service (core state moved).
    _chaosModeService.clearDeliveredPendingIfAny();

    // ── OOC Time-Skip Detection ───────────────────────────────────────────
    if (_realismActiveThisMode) {
      _timeService.detectOocTimeSkip(text);
    }

    // ── Chaos Mode: check + pause for wheel if triggered ─────────────────
    // Guard + tick delegated (pendingInjection check via service getter).
    if (_chaosModeService.chaosModeEnabled &&
        _chaosModeService.pendingChaosInjection == null) {
      if (checkAndTickChaosPressure()) {
        // Create a completer so sendMessage pauses here until the wheel resolves
        _chanceTimeCompleter = Completer<void>();
        _chanceTimePendingTrigger = true;
        notifyListeners(); // UI observes this to show the wheel
        // Wait for the user to spin + accept fate (completes in applyChanceTimeResult)
        await _chanceTimeCompleter!.future;
        _chanceTimeCompleter = null;
      }
    }

    // Note: depth decrement happens after AI response completes (see _generateResponse finalization).
    // This ensures lore triggered by the user message is visible in the current turn's prompt.

    // Check objective task completion BEFORE generating response
    // so the AI gets the updated task in its prompt
    await _maybeCheckTaskCompletionSync();

    // Evaluate realism systems before generating response
    // Capture pre-turn needs vector (before decay + fulfillment) so that
    // regenerateLastMessage() and the post-generation delta computation
    // can use the same delta-revert mechanism the classic realism fields
    // (bond/trust/arousal) use.
    Map<String, int>? preTurnVector;
    // For group chips, snapshot the *pre-decay* needs for the *upcoming* speaker (from map)
    // before tickDecay runs. This lets the post-gen chip deltas include the turn's decay + scene
    // effects (1:1 parity). The per-speaker pre-eval will see the post-decay value after load.
    Map<String, int>? groupSpeakerPreDecayNeeds;
    if (_realismActiveThisMode) {
      if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
        preTurnVector = Map<String, int>.from(_needsSimulation.vector);
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['needs_pre_turn_vector'] = preTurnVector;
      }

      if (_activeGroup != null &&
          _needsSimEnabled &&
          isGroupRealismActive &&
          !_observerMode) {
        final upcoming = nextCharacter;
        if (upcoming != null) {
          final sid = _getCharacterIdFromCard(upcoming);
          if (sid.isNotEmpty) {
            groupSpeakerPreDecayNeeds = _getGroupNeeds(sid);
          }
        }
      }

      _applyMoodDecay();
      _needsSimulation.tickDecay();
      _nsfwService.decrementCooldownIfActive();
      _isEvaluatingRealism = true;
      _realismEvalStreamText = '';
      notifyListeners();

      void handleChunk(String chunk) {
        _realismEvalStreamText += chunk;
        // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
        _evalChunkTimer?.cancel();
        _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
          try {
            notifyListeners();
          } catch (_) {
            // Widget was deactivated — timer fired after navigation
          }
        });
      }

      // Group chats use per-speaker realism evaluation inside _generateResponse
      // (right after speaker selection via _pickNextGroupCharacter). This is the
      // core of Phase 1: the character about to reply gets their own LLM eval.
      final bool skipCentralizedEvalForGroup =
          _activeGroup != null && isGroupRealismActive && !_observerMode;

      if (skipCentralizedEvalForGroup) {
        debugPrint(
          '[Realism:Group] Skipping centralized LLM eval block — per-speaker evaluation will run inside _generateResponse for the upcoming speaker',
        );
      } else if (_relationshipService.pendingTrustRepair) {
        _relationshipService
            .consumePendingTrustRepair(); // consume — resets for next drop
        await _evaluateTrustRepairCall(text, onChunk: handleChunk);

        if (!_realismEvalCancelled) {
          // Wire the realism_state into pending for snapshot/timeline use.
          // (Fulfillment verification is now post-response so it adds zero
          // latency to the pre-response realism phase.)
          _pendingRealismMetadata ??= {};
          _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
          _pendingRealismMetadata!['realism_state'] = _captureRealismState(
            preTurn: preTurnVector,
          );
          _saveChat();
        }

        // Check for cancellation after trust repair eval
        if (_realismEvalCancelled) {
          debugPrint(
            '[Realism] Evaluation cancelled during trust repair, aborting',
          );
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          _evalChunkTimer?.cancel();
          _evalChunkTimer = null;
          _isEvaluatingRealism = false;
          notifyListeners();
          return;
        }
      } else {
        // Fire all evals concurrently.
        if (_storageService.realismSettings.realismOneShotEval) {
          await _evaluateOneShotCall(onChunk: handleChunk);
        } else {
          await Future.wait([
            _evaluateRelationshipCall(
              onChunk: handleChunk,
            ), // step 10 thins (full in realism_evals)
            _evaluateEmotionalStateCall(onChunk: handleChunk),
            _evaluatePhysicalStateCall(onChunk: handleChunk),
            _evaluateNarrativeCall(onChunk: handleChunk),
          ]);
        }

        // Check for cancellation after evals complete but before saving
        if (_realismEvalCancelled) {
          debugPrint(
            '[Realism] Evaluation cancelled during/after evals, aborting',
          );
          _realismEvalCancelled =
              false; // Reset the flag so future messages can proceed
          _evalChunkTimer?.cancel();
          _evalChunkTimer = null;
          _isEvaluatingRealism = false;
          notifyListeners();
          return;
        }

        // Synthesize metadata after all evals complete
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
        _pendingRealismMetadata!['realism_state'] = _captureRealismState(
          preTurn: preTurnVector,
        );

        debugPrint(
          '[Realism:Metadata] Synthesized metadata before generation: bond_delta=${_pendingRealismMetadata?['bond_delta']}, trust_delta=${_pendingRealismMetadata?['trust_delta']}, keys=${_pendingRealismMetadata?.keys.toList()}',
        );
        _saveChat();
      }

      // Cancel any pending debounce notify before closing the overlay
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      await Future.delayed(const Duration(milliseconds: 500));
      _isEvaluatingRealism = false;
      notifyListeners();
    }

    // If cancellation was requested during realism evaluation, abort generation
    if (_realismEvalCancelled) {
      await _saveChat();
      _realismEvalCancelled = false;
      notifyListeners();
      return;
    }

    await _generateResponse(GenerationMode.normal);

    // Long-gen decay removed with buffers (decay via tick only now; model deltas via impact).
    // Compute needs_deltas AFTER generation so the post-generation checks
    // (climax, sexual activity, daily activities, fulfillment) are reflected.
    // This ensures UI chips show accurate deltas.
    if (_needsSimEnabled && _messages.isNotEmpty) {
      if (_activeGroup == null) {
        // 1:1 path: preTurnVector captured in this scope (pre-tick) is correct.
        final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
          preTurnVector ?? const <String, int>{},
        );
        if (needsDeltas.isNotEmpty) {
          _messages.last.activeMetadata ??= {};
          _messages.last.activeMetadata!['needs_deltas'] = needsDeltas;
          await _saveChat();
          notifyListeners();
        }
      } else {
        // Group: use the pre-decay snapshot for this speaker (captured before tick using nextCharacter)
        // so chips reflect the full net turn effect (decay + scene deltas) for 1:1 parity.
        // Fall back to the vector embedded in the per-speaker realism_state snapshot (post-decay)
        // if the pre-decay snapshot wasn't available (e.g. edge rotation).
        final preVec =
            groupSpeakerPreDecayNeeds ??
            _coerceNeedsVector(
              ((_messages.last.activeMetadata?['realism_state']
                      as Map<String, dynamic>?)?['needs']?['vector']),
            );
        if (preVec.isNotEmpty) {
          final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
            preVec,
          );
          if (needsDeltas.isNotEmpty) {
            _messages.last.activeMetadata ??= {};
            _messages.last.activeMetadata!['needs_deltas'] = needsDeltas;
            await _saveChat();
            notifyListeners();
          }
        }
      }
    }
  }

  /// Set observer mode on/off.
  void setObserverMode(bool value) {
    _observerMode = value;
    if (!value) {
      _autoPlayActive = false;
    }
    notifyListeners();
  }

  /// Send a director note — appears as a bracketed instruction in the prompt
  /// but is not part of the in-story dialogue.
  Future<void> sendDirectorNote(String text) async {
    if (_activeGroup == null || text.trim().isEmpty) return;

    _messages.add(
      ChatMessage(
        text: text,
        sender: 'Director',
        isUser: true,
        characterId: '__director__',
      ),
    );
    await _saveChat();
    notifyListeners();

    _lorebookScanner.scanLorebook(text);
    // Note: depth decrement happens after AI response completes inside _generateResponse.
    // Director-triggered lore is visible for the current generate.

    await _generateResponse(GenerationMode.normal);
  }

  /// Start auto-play: characters keep chatting automatically.
  void startAutoPlay() {
    if (_activeGroup == null || !_observerMode) return;
    _autoPlayActive = true;
    notifyListeners();
    _autoPlayNext();
  }

  /// Stop auto-play.
  void stopAutoPlay() {
    _autoPlayActive = false;
    notifyListeners();
  }

  /// Internal: trigger the next auto-play response.
  Future<void> _autoPlayNext() async {
    if (!_autoPlayActive || !_observerMode || _activeGroup == null) return;
    if (_isGenerating) return; // wait for current generation to finish

    await _generateResponse(GenerationMode.normal);
  }

  Future<void> manualReprocessNeeds(int index, String critique) async {
    if (index < 0 || index >= _messages.length) return;
    if (index != _messages.length - 1) return;
    
    final msg = _messages[index];
    if (msg.isUser || msg.sender == 'System') return;
    
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return;
    
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return;
    
    final oldNeedsDeltas = <String, int>{};
    if (meta.containsKey('needs_deltas')) {
      final oldMap = meta['needs_deltas'] as Map;
      for (final k in oldMap.keys) {
        if (oldMap[k] is Map && oldMap[k]['delta'] is num) {
          oldNeedsDeltas[k.toString()] = (oldMap[k]['delta'] as num).toInt();
        }
      }
    }
    
    _needsSimulation.restoreFromSnapshot(preState['needs']);
    final Map<String, int> restoredPreVector = Map<String, int>.from(_needsSimulation.vector);
    
    _isVerifyingRealism = true;
    _verificationPass = 1;
    _verificationMaxPasses = 1;
    notifyListeners();
    
    _pendingRealismMetadata = null;
    
    await _needsImpactEvaluator.reprocessWithUserCritique(msg.displayText, oldNeedsDeltas, critique);
    
    final updatedMeta = Map<String, dynamic>.from(meta);
    updatedMeta['needs_deltas'] = _needsSimulation.computeNeedsDeltasWithReasons(restoredPreVector);
    
    if (_pendingRealismMetadata != null) {
      for (final e in _pendingRealismMetadata!.entries) {
        updatedMeta[e.key] = e.value;
      }
    }
    
    msg.swipeMetadata[msg.swipeIndex] = updatedMeta;
    
    _isVerifyingRealism = false;
    _pendingRealismMetadata = null;
    await _saveChat();
    notifyListeners();
  }

  Future<void> regenerateLastMessage() async {
    if (_messages.isEmpty || _isGenerating) return;

    // Check if the last message is from the character
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      // Instead of removing the message, we generate a new swipe
      // Temporarily remove the last message so the prompt doesn't include it
      final lastMsg = _messages.removeLast();
      notifyListeners();

      // In group mode, force the turn manager to the *original* speaker of the
      // removed message before generation. This prevents regen from picking a
      // different character (the core of the "speaker changed after regen" bug).
      if (_activeGroup != null) {
        final originalSpeaker = _groupCharacters.firstWhere(
          (c) => c.name == lastMsg.sender,
          orElse: () => _groupCharacters.first,
        );
        _groupManager?.setNextSpeaker(originalSpeaker);
      }

      // Revert realism state from the rejected swipe and re-evaluate
      if (_realismEnabled && _activeGroup == null) {
        // CRITICAL FIX: Find the baseline realism state from the previous accepted message.
        // We want to use the final state of the LAST ACCEPTED character message as our baseline,
        // not just blindly revert deltas and re-evaluate from scratch.
        Map<String, dynamic>? previousMessageState;
        if (_messages.length >= 2) {
          // Look back through messages to find the last bot message before the one we're regenerating
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (!_messages[i].isUser && _messages[i].sender != 'System') {
              final meta = _messages[i].activeMetadata;
              if (meta != null && meta.containsKey('realism_state')) {
                previousMessageState =
                    meta['realism_state'] as Map<String, dynamic>;
                debugPrint(
                  '[Realism:Regen] Found previous accepted message baseline state at message index $i',
                );
                break;
              }
            }
          }
        }

        bool wasNudged = false;
        if (lastMsg.activeMetadata != null &&
            lastMsg.activeMetadata!['realism_state'] is Map) {
          wasNudged =
              lastMsg.activeMetadata!['realism_state']['time_nudged'] == true;
        }

        if (lastMsg.activeMetadata != null) {
          final bondDelta = lastMsg.activeMetadata!['bond_delta'] as int? ?? 0;
          final moodDelta = lastMsg.activeMetadata!['mood_delta'] as int? ?? 0;
          final arousalDelta =
              lastMsg.activeMetadata!['arousal_delta'] as int? ?? 0;
          final trustDelta =
              lastMsg.activeMetadata!['trust_delta'] as int? ?? 0;

          if (bondDelta != 0) {
            _relationshipService.applyScoreDelta(-bondDelta);
          }
          if (moodDelta != 0) {
            _moodDecayCounter = 0;
          }
          if (trustDelta != 0) {
            _relationshipService.setTrustLevelForRevert(
              (_relationshipService.trustLevel - trustDelta).clamp(-100, 100),
            );
          }

          // Revert climax state if this response triggered refractory cooldown.
          // The climax checker stores the pre-climax arousal so we can restore it.
          final climaxTriggered =
              lastMsg.activeMetadata!['climax_triggered'] as bool? ?? false;
          if (climaxTriggered && _nsfwService.nsfwCooldownEnabled) {
            final preClimaxArousal =
                lastMsg.activeMetadata!['pre_climax_arousal'] as int? ?? 0;
            _nsfwService.setArousalLevel(preClimaxArousal);
            _nsfwService.setCooldownTurnsRemaining(0);
            _nsfwService.setCooldownTurnsTotal(0);
            debugPrint(
              '[Realism:Regen] Reverted climax state: arousal restored to $preClimaxArousal, cooldown cleared',
            );
          } else if (arousalDelta != 0 && _nsfwService.nsfwCooldownEnabled) {
            // Normal arousal delta revert (no climax involved)
            _nsfwService.setArousalLevel(
              (_nsfwService.arousalLevel - arousalDelta).clamp(-100, 100),
            );
          }

          // Needs pre-turn vector revert — mirrors the bond/trust/arousal delta
          // system so regen can undo the decay + fulfillment that ran for this
          // user turn, even when the previous message's realism_state snapshot
          // lacks a 'needs' entry (e.g. needs was enabled mid-chat).
          final preTurnNeeds =
              lastMsg.activeMetadata!['needs_pre_turn_vector'] as Map?;
          if (preTurnNeeds != null && _needsSimEnabled) {
            _needsSimulation.restoreFromSnapshot({
              'vector': Map<String, int>.from(preTurnNeeds),
            });
            debugPrint(
              '[Realism:Regen] Restored needs vector from pre-turn snapshot on rejected message',
            );
          }
        }

        // CRITICAL FIX: Restore the baseline state from the previous accepted message.
        // This ensures the new regenerated message is evaluated against the correct baseline,
        // not from scratch which would produce wildly different realism values.
        if (previousMessageState != null) {
          _relationshipService.restoreFromMessageState(previousMessageState);
          _moodDecayCounter =
              previousMessageState['moodDecayCounter'] as int? ??
              _moodDecayCounter;
          _characterEmotion =
              previousMessageState['characterEmotion'] as String? ??
              _characterEmotion;
          _emotionIntensity =
              previousMessageState['emotionIntensity'] as String? ??
              _emotionIntensity;

          _timeService.restoreTimeForSwipeOrRegen(
            previousMessageState,
            wasNudged: wasNudged,
          );

          _nsfwService.restoreNsfwFromMessageState(previousMessageState);

          // Needs simulation snapshot (clean port)
          // Guard + no enabled override: prevents stale resurrection on regen after toggle-off.
          if (previousMessageState.containsKey('needs') &&
              previousMessageState['needs'] is Map &&
              _needsSimEnabled) {
            final needsData = previousMessageState['needs'] as Map;
            if (needsData['vector'] is Map) {
              final vector = Map<String, int>.from(needsData['vector'] as Map);
              _needsSimulation.restoreFromSnapshot({'vector': vector});
            }
          }

          debugPrint(
            '[Realism:Regen] ✓ Restored baseline from previous accepted message: bond=${_relationshipService.affectionScore}, emotion=$_characterEmotion, trust=${_relationshipService.trustLevel}, arousal=${_nsfwService.arousalLevel}',
          );
        } else {
          debugPrint(
            '[Realism:Regen] ⚠ No previous message baseline found, continuing with current reverted state',
          );
        }
        // Set UI streaming state
        _isEvaluatingRealism = true;
        _realismEvalStreamText = '';
        notifyListeners();

        void handleChunk(String chunk) {
          _realismEvalStreamText += chunk;
          // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
          _evalChunkTimer?.cancel();
          _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
            try {
              notifyListeners();
            } catch (_) {
              // Widget was deactivated — timer fired after navigation
            }
          });
        }

        // Apply decay and cooldown — mirrors the normal path (lines 3933-3937).
        // This ensures _needsVector differs from the saved pre-turn vector
        // so post-generation deltas are non-zero.
        _applyMoodDecay();
        _needsSimulation.tickDecay();
        _nsfwService.decrementCooldownIfActive();

        // Record the (restored) needs baseline as the pre-turn vector BEFORE
        // generation so the post-generation checks can compute proper deltas.
        if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
          _pendingRealismMetadata ??= {};
          _pendingRealismMetadata!['needs_pre_turn_vector'] =
              Map<String, int>.from(_needsSimulation.vector);
        }

        if (_storageService.realismSettings.realismOneShotEval) {
          await _evaluateOneShotCall(onChunk: handleChunk);
        } else {
          await Future.wait([
            _evaluateRelationshipCall(
              onChunk: handleChunk,
            ), // step 10 thins (full in realism_evals)
            _evaluateEmotionalStateCall(onChunk: handleChunk),
            _evaluatePhysicalStateCall(onChunk: handleChunk),
            _evaluateNarrativeCall(onChunk: handleChunk),
          ]);
        }

        // Check for cancellation after evals complete
        if (_realismEvalCancelled) {
          debugPrint(
            '[Realism] Evaluation cancelled during regenerate, aborting',
          );
          _realismEvalCancelled = false;
          _evalChunkTimer?.cancel();
          _evalChunkTimer = null;
          _isEvaluatingRealism = false;
          notifyListeners();
          return;
        }

        // Cancel any pending debounce notify before closing the overlay
        _evalChunkTimer?.cancel();
        _evalChunkTimer = null;
        _isEvaluatingRealism = false;
        notifyListeners();
      }

      // In group mode the per-speaker realism eval (and its metadata / needs deltas)
      // happens inside _generateResponse via _evaluateRealismForUpcomingGroupSpeaker
      // for the correctly-forced speaker. Skip the 1:1 scalar synthesis here.
      Map<String, int>? regenPreTurn;
      Map<String, dynamic>? needsDeltas;
      if (_activeGroup == null) {
        // Save pre-turn vector BEFORE _generateResponse (which clears
        // _pendingRealismMetadata).
        regenPreTurn =
            _pendingRealismMetadata?['needs_pre_turn_vector']
                as Map<String, int>?;

        // Synthesize metadata after all regen evals complete — mirrors the
        // normal path (line 4020) so emotion_label and realism_state are in
        // _pendingRealismMetadata before _generateResponse consumes it.
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
        _pendingRealismMetadata!['realism_state'] = _captureRealismState(
          preTurn: regenPreTurn,
        );

        // If cancellation was requested during realism evaluation, abort generation
        if (_realismEvalCancelled) {
          _realismEvalCancelled = false;
          notifyListeners();
          return;
        }
      }

      // Invalidate ONNX cache for the new response (delegated)
      _expressionService.invalidateOnnxCacheForNewResponse();

      // Generate into a new message — it will be appended by _generateResponse.
      // _generateResponse runs the post-generation needs checks (climax,
      // sexual activity, daily activities, fulfillment) which modify the
      // needs vector. We need to compute needs_deltas AFTER generation.
      await _generateResponse(GenerationMode.normal);

      // Compute needs_deltas AFTER generation so the post-generation checks
      // are reflected. This mirrors the normal generation path (line ~4053).
      // Apply directly to the message since _pendingRealismMetadata was consumed.
      // (For groups, the per-speaker path inside generate already attached the
      // correct per-character needs_deltas; we only compute scalar here for 1:1.)
      if (_activeGroup == null &&
          _needsSimEnabled &&
          _needsSimulation.vector.isNotEmpty) {
        needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
          regenPreTurn ?? const <String, int>{},
        );
      }

      // After generation, merge the new response as a swipe on the original message
      if (_messages.isNotEmpty &&
          !_messages.last.isUser &&
          _messages.last.sender != 'System') {
        final newText = _messages.last.text;
        final newMetadata = _messages.last.activeMetadata;
        _messages.removeLast();
        lastMsg.swipes.add(newText);
        lastMsg.swipeIndex = lastMsg.swipes.length - 1;
        // Merge needs_deltas into the swipe metadata
        if (needsDeltas != null && needsDeltas.isNotEmpty) {
          lastMsg.activeMetadata = {
            ...(newMetadata ?? {}),
            'needs_deltas': needsDeltas,
          };
        } else {
          lastMsg.activeMetadata = newMetadata;
        }
        _messages.add(lastMsg);
        await _saveChat();
        notifyListeners();

        // In group mode, advance the turn pointer past the regenerated speaker
        // so the next natural generation continues the correct rotation instead
        // of repeating the same character.
        if (_activeGroup != null) {
          final originalSpeaker = _groupCharacters.firstWhere(
            (c) => c.name == lastMsg.sender,
            orElse: () => _groupCharacters.first,
          );
          _groupManager?.advanceAfterRegeneration(originalSpeaker);
        }
      }
    }
  }

  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(int messageIndex, int direction) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    final oldIndex = msg.swipeIndex;

    // Swiping left
    if (direction < 0) {
      if (newIndex >= 0) {
        msg.swipeIndex = newIndex;
        _syncRealismStateForSwipe(msg, oldIndex, newIndex);
        await _saveChat();
        notifyListeners();
      }
      return;
    }

    // Swiping right
    if (newIndex < msg.swipes.length) {
      // Navigate to existing swipe
      msg.swipeIndex = newIndex;
      _syncRealismStateForSwipe(msg, oldIndex, newIndex);
      await _saveChat();
      notifyListeners();
    } else if (messageIndex == _messages.length - 1 && !_isGenerating) {
      // Past last swipe on last message — regenerate
      await regenerateLastMessage();
    }
  }

  void _syncRealismStateForSwipe(ChatMessage msg, int oldIndex, int newIndex) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate timeline
    _restoreRealismStateFromMessage(msg);
  }

  Future<void> continueGeneration() async {
    if (_messages.isEmpty || _isGenerating) return;

    // Only continue if the last message is from a bot (non-user, non-system)
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      await _generateResponse(GenerationMode.continue_);
    }
  }

  Future<void> impersonateUser({
    String prefix = '',
    required Function(String accumulated) onToken,
  }) async {
    if ((_activeCharacter == null && _activeGroup == null) || _isGenerating) {
      return;
    }

    _isGenerating = true;
    _cancelRequested = false;
    notifyListeners();

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character (needed for prompt construction)
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter = _groupCharacters.first;
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // Build prompt the same way _generateResponse does
      // Path B clean hierarchy (same as the main generation path)
      String systemPrompt;
      if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
        systemPrompt = _applyUserReplacement(_activeGroup!.systemPrompt);
      } else if (_activeGroup != null) {
        systemPrompt = _observerMode
            ? observerModeSystemPrompt
            : defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.generationSettings.systemPrompt.isNotEmpty) {
        systemPrompt = _storageService.generationSettings.systemPrompt;
      } else {
        final isApi = _llmProvider != null && !_llmProvider!.isLocal;
        systemPrompt = isApi
            ? defaultApiSystemPrompt
            : defaultKoboldSystemPrompt;
      }

      if (_activeGroup != null) {
        final groupCharPrompt = getSystemPromptForGroupCharacter(
          speakingCharacter,
        ).trim();
        if (groupCharPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Group-specific instructions for ${speakingCharacter.name}]\n$groupCharPrompt';
        } else if (speakingCharacter.systemPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Specific instructions for ${speakingCharacter.name}]\n${speakingCharacter.systemPrompt.trim()}';
        }
      }

      // Lorebook (group + per-character, respecting inherit flag and group worlds)
      String loreContent = '';
      final activeLoreStrings = <String>{}; // Set for deduplication

      final inherit = _activeGroup?.inheritCharacterLorebooks ?? true;

      // Group-level lorebook (highest priority when present)
      if (_activeGroup != null && _activeGroup!.groupLorebook.isNotEmpty) {
        try {
          final json = jsonDecode(_activeGroup!.groupLorebook);
          final gl = Lorebook.fromJson(json as Map<String, dynamic>);
          final active = gl.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(active.map((e) => e.content));
        } catch (_) {}
      }

      // Group-level worlds (always included if attached to the group)
      if (_activeGroup != null) {
        for (final wid in _activeGroup!.worldIds) {
          final world = _worldRepository.worlds
              .where((w) => w.name == wid)
              .firstOrNull;
          if (world == null) continue;
          final active = world.lorebook.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(active.map((e) => e.content));
        }
      }

      // Per-character lore and their worlds (only if inherit is true or no group)
      if (inherit || _activeGroup == null) {
        final loreCharacters = _activeGroup != null
            ? _groupCharacters
            : (_activeCharacter != null
                  ? [_activeCharacter!]
                  : <CharacterCard>[]);
        for (final ch in loreCharacters) {
          if (ch.lorebook != null) {
            final activeEntries = ch.lorebook!.entries.where(
              (e) => e.enabled && (e.isTriggered || e.constant),
            );
            activeLoreStrings.addAll(activeEntries.map((e) => e.content));
          }
          for (final worldName in ch.worldNames) {
            final world = _worldRepository.worlds
                .where((w) => w.name == worldName)
                .firstOrNull;
            if (world == null) continue;
            final activeWorldEntries = world.lorebook.entries.where(
              (e) => e.enabled && (e.isTriggered || e.constant),
            );
            activeLoreStrings.addAll(activeWorldEntries.map((e) => e.content));
          }
        }
      }

      if (activeLoreStrings.isNotEmpty) {
        loreContent = "Context Info:\n${activeLoreStrings.join('\n')}\n";
        loreContent = speakingCharacter.replacePlaceholders(
          loreContent,
          userName: userName,
        );
      }

      // Persona & scenario
      // Use evolved versions if character evolution is enabled and available
      String personaBlock;
      if (_activeGroup != null) {
        final personas = _groupCharacters
            .map(
              (ch) =>
                  "${ch.name}'s Persona: ${ch.replacePlaceholders(_getEffectivePersonality(ch), userName: userName)}",
            )
            .toList();
        personaBlock = personas.join('\n');
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${speakingCharacter.replacePlaceholders(_getEffectivePersonality(speakingCharacter), userName: userName)}";
      }

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = await _buildUserPersonaBlock(userName);

      String rawScenario = '';
      if (_activeGroup != null && _activeGroup!.scenario.isNotEmpty) {
        rawScenario = _activeGroup!.scenario;
      } else {
        final scenarioChar = _activeGroup != null
            ? _groupCharacters.first
            : speakingCharacter;
        rawScenario = _getEffectiveScenario(scenarioChar);
      }
      final scenario = speakingCharacter.replacePlaceholders(
        rawScenario,
        userName: userName,
      );

      String history = _buildChatHistory();

      // Suffix: user name + any partial text the user typed
      String suffix = "\n$userName:";
      if (prefix.isNotEmpty) {
        suffix = "$suffix $prefix";
      }

      String mesExampleBlock = '';
      if (_activeGroup != null) {
        final examples = _groupCharacters
            .where((ch) => ch.mesExample.isNotEmpty)
            .map(
              (ch) => ch.replacePlaceholders(ch.mesExample, userName: userName),
            )
            .toList();
        if (examples.isNotEmpty) {
          mesExampleBlock = '${examples.join('\n')}\n';
        }
      } else if (speakingCharacter.mesExample.isNotEmpty) {
        mesExampleBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.mesExample, userName: userName)}\n';
      }

      String postHistoryBlock = '';
      if (_activeGroup == null &&
          speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.postHistoryInstructions, userName: userName)}\n';
      }

      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // Impersonate instruction — comprehensive guidance for writing as the user
      final impersonateInstruction =
          '[System: You are now writing as $userName (the user), NOT as ${speakingCharacter.name} or any other character. '
          'Compose $userName\'s next message in first person. '
          'Match $userName\'s established voice, personality, and writing style from the conversation so far. '
          'Write only $userName\'s words and actions — never narrate for ${speakingCharacter.name} or other characters. '
          'Do not include meta-commentary, stage directions for others, or break the fourth wall. '
          'Keep the response natural, and consistent with the scene.]\n';

      // ── Context Shift: budget-aware history trimming ──
      final fixedContent =
          "$systemPrompt\n"
          "$loreContent"
          "$personaBlock\n"
          "$userPersonaBlock"
          "Scenario: $scenario\n"
          "$mesExampleBlock"
          "<START>\n"
          "$postHistoryBlock"
          "$authorNoteBlock"
          "$impersonateInstruction"
          "$suffix";
      final fixedTokens = await _countTokens(fixedContent);
      final contextBudget = _sessionGenSettings.resolveContextSize(
        _storageService,
      );
      final generationReserve =
          _sessionGenSettings.resolveMaxLength(_storageService) + 50;
      final historyBudget = contextBudget - fixedTokens - generationReserve;

      if (historyBudget > 0) {
        final result = await _buildChatHistoryWithBudget(historyBudget);
        history = result.history;
      } else if (_messages.isNotEmpty) {
        final lastMsg = _messages.last;
        history = lastMsg.characterId == '__director__'
            ? '[Director: ${lastMsg.text}]'
            : '${lastMsg.sender}: ${lastMsg.text}';
      }

      // For chat APIs (OpenRouter, LM Studio), separate the system prompt
      // so it can be sent as a proper 'system' role message.
      final isRemoteApi = _llmProvider != null && !_llmProvider!.isLocal;
      final chatSystemPrompt = isRemoteApi
          ? "$systemPrompt\n$loreContent$personaBlock\n$userPersonaBlock"
                "Scenario: $scenario\n$mesExampleBlock"
          : null;

      final prompt = isRemoteApi
          ? "<START>\n"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$impersonateInstruction"
                "$suffix"
          : "$systemPrompt\n"
                "$loreContent"
                "$personaBlock\n"
                "$userPersonaBlock"
                "Scenario: $scenario\n"
                "$mesExampleBlock"
                "<START>\n"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$impersonateInstruction"
                "$suffix";

      // Stop sequences: character names only (not user — we ARE the user)
      final g = _sessionGenSettings;
      final stopSequences = {
        ...g.resolveStopSequences(_storageService).toSet(),
      };
      if (_activeGroup != null) {
        for (final ch in _groupCharacters) {
          stopSequences.add('\n${ch.name}:');
        }
      } else {
        stopSequences.add('\n${_activeCharacter!.name}:');
      }

      final llmService =
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService;
      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
        maxLength: g.resolveMaxLength(_storageService),
        minLength: g.resolveMinLength(_storageService),
        minP: g.resolveMinP(_storageService),
        temperature: g.resolveTemperature(_storageService),
        repeatPenalty: g.resolveRepeatPenalty(_storageService),
        repPenTokens: g.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g.resolveDynamicTempEnabled(_storageService)
            ? g.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g.resolveXtcThreshold(_storageService),
        xtcProbability: g.resolveXtcProbability(_storageService),
        stopSequences: stopSequences.toList(),
        reasoningEnabled: false,
        reasoningEffort: g.resolveReasoningEffort(_storageService),
        bannedPhrases: g.resolveBannedPhrases(_storageService).isNotEmpty
            ? g.resolveBannedPhrases(_storageService)
            : null,
      );

      final stream = llmService.generateStream(genParams);
      String accumulated = prefix;
      bool inThinkBlock = false;

      await for (final token in stream) {
        if (_cancelRequested) break;
        // Filter out <think>...</think> reasoning blocks entirely
        if (token.contains('<think>')) {
          inThinkBlock = true;
          continue;
        }
        if (token.contains('</think>')) {
          inThinkBlock = false;
          continue;
        }
        if (inThinkBlock) continue;
        accumulated += token;
        onToken(accumulated);
      }
    } catch (e) {
      print('Impersonate error: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() async {
    if (_activeGroup == null || _groupCharacters.isEmpty || _isGenerating) {
      return;
    }
    await _generateResponse(GenerationMode.normal);
  }

  /// Manually select which character speaks next in group mode.
  /// Delegated to GroupTurnManager.
  void setNextCharacter(CharacterCard character) {
    _groupManager?.setNextSpeaker(character);
    notifyListeners(); // ensure UI updates even if manager didn't notify

    // In group mode, switch the active objectives to this character's personal ones.
    if (_activeGroup != null) {
      _loadObjectivesForCurrentSpeaker();
    }
  }

  /// Pick which character speaks next based on turn order.
  /// A _forcedNextSpeakerId (set by manual user choice) is consumed first
  /// and works for both TurnOrder.random and roundRobin. After consumption
  /// we resume normal cycling / random behavior.
  CharacterCard _pickNextGroupCharacter() {
    if (_groupManager == null) {
      throw StateError('No active group');
    }
    return _groupManager!.pickNextSpeaker();
  }

  /// Returns the stable charId of the character whose realism state should be
  /// read/written for the current turn. In group mode this is the speaker
  /// we are about to generate for (or just generated for).
  String _getCurrentSpeakerIdForRealism() {
    if (_activeGroup == null || _groupCharacters.isEmpty) {
      return _getCharacterId();
    }
    final next = nextCharacter;
    if (next != null) {
      return _getCharacterIdFromCard(next);
    }
    return _getCharacterIdFromCard(_groupCharacters.first);
  }

  // ── Per-character realism state helpers (group mode) ────────────────────
  void _setGroupRealismValue(String charId, String key, dynamic value) {
    if (_activeGroup == null) return;
    _groupRealism.putIfAbsent(charId, () => <String, dynamic>{});
    _groupRealism[charId]![key] = value;
  }

  int _getGroupInt(String charId, String key, {int defaultValue = 0}) =>
      (_groupRealism[charId]?[key] as num?)?.toInt() ?? defaultValue;

  String _getGroupString(
    String charId,
    String key, {
    String defaultValue = '',
  }) => (_groupRealism[charId]?[key] as String?) ?? defaultValue;

  // Tolerant coercion for a needs vector that may arrive as JSON-decoded
  // (num values), dynamic map from metadata/snapshots/pre_state, or proper
  // Map<String,int>. Used for pre-turn vectors in chips, restores, and fallbacks.
  Map<String, int> _coerceNeedsVector(dynamic src) {
    if (src == null) return const {};
    if (src is Map<String, int>) return Map<String, int>.from(src);
    if (src is Map) {
      final out = <String, int>{};
      src.forEach((k, v) {
        final key = k.toString();
        if (v is num) {
          out[key] = v.toInt();
        } else if (v is int) {
          out[key] = v;
        }
      });
      return out;
    }
    return const {};
  }

  Map<String, int> _getGroupNeeds(String charId) {
    final raw = _groupRealism[charId]?['needs'];
    final result = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final v = (raw is Map) ? raw[k] : null;
      if (v is num) {
        result[k] = v.toInt();
      } else {
        result[k] = NeedsSimulation.needDefaults[k] ?? 80;
      }
    }
    return result;
  }

  void _setGroupNeeds(String charId, Map<String, int> needs) {
    _setGroupRealismValue(charId, 'needs', needs);
  }

  // ensureInterCharacterRelationshipsSeeded / updateInterCharacterFeelingsFromRecentExchange
  // moved verbatim to RelationshipService (with callbacks for group/messages). Old bodies deleted.

  Future<void> _generateResponse(GenerationMode mode) async {
    final epoch = ++_generationEpoch;
    _isGenerating = true;
    _generationProgress = 0.0;
    _tokensGenerated = 0;
    _maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _generationStartTime = DateTime.now();
    _isBuffering = true;
    _generationPhase = GenerationPhase.preparing;
    _prefillStartTime = null;
    _lastPerfData = null;
    _sentenceBuffer = '';
    notifyListeners();

    // Track original model for call mode swap/restore (needs to be outside try/catch)
    String? _originalModelName;

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter =
            (mode == GenerationMode.continue_ &&
                _messages.isNotEmpty &&
                !_messages.last.isUser)
            ? _groupCharacters.firstWhere(
                (c) => c.name == _messages.last.sender,
                orElse: () => _pickNextGroupCharacter(),
              )
            : _pickNextGroupCharacter();
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // Phase 1: Per-character realism evaluation for the upcoming speaker in groups.
      // We evaluate the specific character who is about to reply, before building their prompt.
      if (_activeGroup != null && isGroupRealismActive && !observerMode) {
        await _evaluateRealismForUpcomingGroupSpeaker(speakingCharacter);
      }

      // ── System prompt selection (Path B clean hierarchy) ──
      // 1. Group-level system prompt (if set) — base for the whole group.
      // 2. Per-character group override (if set for the speaker in this group) — appended.
      // 3. Character's normal card system prompt (fallback if no group override for them).
      // 4. (Later) Per-character Author's Note is injected separately with its own strength.
      String systemPrompt;

      if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
        systemPrompt = _applyUserReplacement(_activeGroup!.systemPrompt);
      } else if (_activeGroup != null) {
        systemPrompt = _observerMode
            ? observerModeSystemPrompt
            : defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.generationSettings.systemPrompt.isNotEmpty) {
        systemPrompt = _storageService.generationSettings.systemPrompt;
      } else {
        final isApi = _llmProvider != null && !_llmProvider!.isLocal;
        systemPrompt = isApi
            ? defaultApiSystemPrompt
            : defaultKoboldSystemPrompt;
      }

      // Path B: When in a group, always attempt to layer the per-character group override
      // (and card fallback) on top. A group prompt no longer completely hides per-char instructions.
      if (_activeGroup != null) {
        final groupCharPrompt = getSystemPromptForGroupCharacter(
          speakingCharacter,
        ).trim();
        if (groupCharPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Group-specific instructions for ${speakingCharacter.name}]\n$groupCharPrompt';
        } else if (speakingCharacter.systemPrompt.isNotEmpty) {
          // Fallback to the character's own card prompt only if no group-specific override
          systemPrompt +=
              '\n\n[Specific instructions for ${speakingCharacter.name}]\n${speakingCharacter.systemPrompt.trim()}';
        }
      }

      // In call mode, inject voice-specific instructions for natural conversation
      if (_callMode &&
          _storageService.sttSettings.callSystemPrompt.isNotEmpty) {
        systemPrompt +=
            '\n\n[Voice Call Mode] ${_storageService.sttSettings.callSystemPrompt}';
      }

      // Build Lorebook content (group + per-character, respecting inherit + group worlds)
      String loreContent = '';
      final activeLoreStrings = <String>{}; // Set for deduplication

      final inherit = _activeGroup?.inheritCharacterLorebooks ?? true;

      // Group-level lorebook (highest priority)
      if (_activeGroup != null && _activeGroup!.groupLorebook.isNotEmpty) {
        try {
          final json = jsonDecode(_activeGroup!.groupLorebook);
          final gl = Lorebook.fromJson(json as Map<String, dynamic>);
          final active = gl.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(active.map((e) => e.content));
        } catch (_) {}
      }

      // Group-level attached worlds
      if (_activeGroup != null) {
        for (final wid in _activeGroup!.worldIds) {
          final world = _worldRepository.worlds
              .where((w) => w.name == wid)
              .firstOrNull;
          if (world == null) continue;
          final active = world.lorebook.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(active.map((e) => e.content));
        }
      }

      // Per-character (only if inheriting or no group)
      if (inherit || _activeGroup == null) {
        final loreCharacters = _activeGroup != null
            ? _groupCharacters
            : [_activeCharacter!];
        for (final ch in loreCharacters) {
          if (ch.lorebook != null) {
            final activeEntries = ch.lorebook!.entries.where(
              (e) => e.enabled && (e.isTriggered || e.constant),
            );
            activeLoreStrings.addAll(activeEntries.map((e) => e.content));
          }
          for (final worldName in ch.worldNames) {
            final world = _worldRepository.worlds
                .where((w) => w.name == worldName)
                .firstOrNull;
            if (world == null) continue;
            final activeWorldEntries = world.lorebook.entries.where(
              (e) => e.enabled && (e.isTriggered || e.constant),
            );
            activeLoreStrings.addAll(activeWorldEntries.map((e) => e.content));
          }
        }
      }

      if (activeLoreStrings.isNotEmpty) {
        loreContent = "Context Info:\n${activeLoreStrings.join('\n')}\n";
      }

      // Apply replacements to lore content
      if (loreContent.isNotEmpty) {
        loreContent = speakingCharacter.replacePlaceholders(
          loreContent,
          userName: userName,
        );
      }

      // Build persona block(s)
      String personaBlock;
      if (_activeGroup != null) {
        personaBlock = _groupCharacters
            .map((ch) {
              final persona = ch.replacePlaceholders(
                _getEffectivePersonality(ch),
                userName: userName,
              );
              return "${ch.name}'s Persona: $persona";
            })
            .join('\n');
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${speakingCharacter.replacePlaceholders(_getEffectivePersonality(speakingCharacter), userName: userName)}";
      }

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = await _buildUserPersonaBlock(userName);

      // Scenario — use group scenario override if set, else first character
      final String rawScenario;
      if (_activeGroup != null && _activeGroup!.scenario.isNotEmpty) {
        rawScenario = _activeGroup!.scenario;
      } else {
        final scenarioChar = _activeGroup != null
            ? _groupCharacters.first
            : speakingCharacter;
        rawScenario = _getEffectiveScenario(scenarioChar);
      }
      final scenario = speakingCharacter.replacePlaceholders(
        rawScenario,
        userName: userName,
      );

      String suffix = "";

      if (mode == GenerationMode.normal) {
        suffix = "\n${speakingCharacter.name}:";
      } else if (mode == GenerationMode.impersonate) {
        suffix = "\n$userName:";
      } else if (mode == GenerationMode.continue_) {
        // Suffix will be set after history is built — see below
        suffix = "";
      }

      // Build example dialogues block
      String mesExampleBlock = '';
      if (_activeGroup != null) {
        final examples = _groupCharacters
            .where((ch) => ch.mesExample.isNotEmpty)
            .map(
              (ch) => ch.replacePlaceholders(ch.mesExample, userName: userName),
            )
            .toList();
        if (examples.isNotEmpty) {
          mesExampleBlock = '${examples.join('\n')}\n';
        }
      } else if (speakingCharacter.mesExample.isNotEmpty) {
        mesExampleBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.mesExample, userName: userName)}\n';
      }

      // Build post-history instructions block
      String postHistoryBlock = '';
      if (_activeGroup == null &&
          speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.postHistoryInstructions, userName: userName)}\n';
      }

      // Author's note — placed right before the character speaks for maximum influence
      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // Per-character Author's Note (group mode only): if the current speaker has
      // a personal note, inject it using the same strength-modulated style.
      // Falls back gracefully (no-op) if absent. Appended after any group-level note.
      if (_activeGroup != null) {
        final charNote = getAuthorNoteForGroupCharacter(speakingCharacter);
        if (charNote.isNotEmpty) {
          // Use per-character strength if set, otherwise fall back to group default
          final s = getAuthorNoteStrengthForGroupCharacter(speakingCharacter);
          final name = speakingCharacter.name;
          String perCharBlock;
          if (s <= 3) {
            perCharBlock =
                "[Author's Note (gentle suggestion for $name): $charNote]\n";
          } else if (s <= 7) {
            perCharBlock = "[Author's Note (for $name): $charNote]\n";
          } else {
            perCharBlock =
                "[Author's Note (IMPORTANT for $name — apply immediately): $charNote]\n";
          }
          authorNoteBlock += perCharBlock;
        }
      }

      // One-shot entrance directive (forked-in character) — hidden, consumed
      // here so it influences only this generation and never persists.
      if (_entranceDirective != null) {
        authorNoteBlock += '[${_entranceDirective!}]\n';
        _entranceDirective = null;
      }

      // Build summary block if available
      String summaryBlock = '';
      if (_summary.isNotEmpty) {
        summaryBlock = '[Summary of events so far: $_summary]\n';
      }

      // ── Continue mode: remove the last message from history ──
      // For continue mode, we exclude the last message from the chat history
      // and place it as the prompt suffix so the LLM continues from it naturally.
      // Wrapped in try-finally to guarantee restoration even on exception.
      ChatMessage? _continuePoppedMessage;
      if (mode == GenerationMode.continue_ && _messages.isNotEmpty) {
        _continuePoppedMessage = _messages.removeLast();
        final partial = _continuePoppedMessage.text;
        // For Continue: feed straight existing messages as the prompt (per user request).
        // The suffix is the raw text of the message being continued (no re-added "Sender: " label).
        // This makes the continuation prompt contain the plain previous messages + the exact
        // partial text to extend, so the model continues the string directly without beginning
        // the output with "Rachel:" or the speaker name.
        // CRITICAL RULE: Strictly forbid the model from writing *anything* for {{user}} (actions, dialogue, thoughts, "he said", "you feel", etc.).
        // This is a cardinal sin in AI RP. Only extend the provided partial text from the current speaker's POV and voice.
        suffix = "\n[CRITICAL RULE: The text below is an incomplete response from the *current speaker only*. You MUST ONLY generate more text that continues *this exact response* in the speaker's voice, style, and perspective. NEVER write any dialogue, actions, thoughts, narration, or descriptions for {{user}} or from {{user}}'s point of view. NEVER add new speaker labels or switch characters. Only append to the text below. Stop if it would require {{user}} content.]\n" + partial;
      }

      // Declare variables before try block so they're accessible after finally
      String history = '';
      String realismBlock = '';
      String chanceTimeBlock = '';
      String objectiveBlock = '';
      String needsCatastropheBlock = '';
      int droppedMessages = 0;

      // Ensure the popped message is always restored, even if prompt assembly throws
      try {
        history = _buildChatHistory();

        // ── Context Shift: budget-aware history trimming ──

        // Realism injection blocks — compute early so they're in the token budget
        // (now via thin _get* delegating to prompt_injection/* builders per step 8)
        if (_realismActiveThisMode) {
          final relationship = _getRelationshipInjection();
          final emotion = _getEmotionInjection();
          final time = _getTimeInjection();
          final trustBehavior = _getTrustBehaviorInjection();
          final cooldown = _getNsfwCooldownInjection();
          final behavioral = _getBehavioralMechanicsInjection();
          final needs = _getNeedsInjection();
          final interCharFeelings = _getInterCharacterFeelingsInjection();
          realismBlock =
              '$relationship$emotion$time$trustBehavior$cooldown$behavioral$needs$interCharFeelings';
        }

        // Chance Time injection — independent of realism mode
        chanceTimeBlock = _getChanceTimeInjection();

        // Objective injection — always injected regardless of realism mode
        // Must sit in a fixed prompt section so it is NEVER trimmed by the budget system.
        // (thin delegation to author_note_builder per step 8; state/CRUD in god)
        objectiveBlock = _getObjectiveInjection();

        // Mandatory Needs Catastrophe (Phase 2 stepping) — when a need hit 0 during
        // the previous decay tick, we force the AI to roleplay the disaster right now.
        if (_needsSimulation.pendingCatastrophe != null) {
          needsCatastropheBlock =
              '[MANDATORY CATASTROPHIC NEED EVENT — THIS HAS ALREADY OCCURRED THIS TURN:\n'
              '${_needsSimulation.pendingCatastrophe}\n'
              'You MUST narrate the immediate physical sensations, the visible evidence '
              '(wet patch/puddle on clothes or floor, her collapsing or fainting, smell, '
              'mortified/embarrassed expression, how {{user}} and anyone else present reacts), '
              'and the emotional/social aftermath in the very first 1-2 paragraphs. '
              'This is not optional, not a suggestion, and not something the character "might" do — '
              'the event is canon and has just happened or is happening right now. '
              'Do not fade to black, do not ask for permission, do not skip it.]\n';
          // Consume it for this generation
          _needsSimulation.consumePendingCatastrophe();
        }

        // Calculate token cost of all fixed sections to determine chat history budget
        final fixedContent =
            "$systemPrompt\n"
            "$loreContent"
            "$personaBlock\n"
            "$userPersonaBlock"
            "Scenario: $scenario\n"
            "$mesExampleBlock"
            "<START>\n"
            "$summaryBlock"
            "$postHistoryBlock"
            "$authorNoteBlock"
            "$objectiveBlock"
            "$realismBlock"
            "$needsCatastropheBlock"
            "$suffix"
            "$chanceTimeBlock";
        final fixedTokens = await _countTokens(fixedContent);
        final contextBudget = _sessionGenSettings.resolveContextSize(
          _storageService,
        );
        final generationReserve =
            _sessionGenSettings.resolveMaxLength(_storageService) +
            50; // +50 safety margin
        final historyBudget = contextBudget - fixedTokens - generationReserve;

        if (historyBudget > 0) {
          final result = await _buildChatHistoryWithBudget(historyBudget);
          history = result.history;
          droppedMessages = result.droppedCount;
        }
        // If budget is zero or negative, fixed sections already fill the context — use minimal history
        if (historyBudget <= 0 && _messages.isNotEmpty) {
          // Include at least the last message for continuity
          final lastMsg = _messages.last;
          history = lastMsg.characterId == '__director__'
              ? '[Director: ${lastMsg.text}]'
              : '${lastMsg.sender}: ${lastMsg.text}';
          droppedMessages = _messages.length - 1;
        }
      } finally {
        // ── Restore the popped continue message back into the list ──
        if (_continuePoppedMessage != null) {
          _messages.add(_continuePoppedMessage);
        }
      }

      if (mode == GenerationMode.continue_) {
        // Drop the needs/realism/relationship/chaos/objective/catastrophe state injections
        // for Continue. Per user request: the continue prompt should be straight existing
        // messages (the plain history transcript + the partial text to continue from).
        // The runtime state blocks make the continuation feel injected and discordant.
        realismBlock = '';
        chanceTimeBlock = '';
        objectiveBlock = '';
        needsCatastropheBlock = '';
        // Also skip RAG "earlier memories" for pure straight continuation.
        droppedMessages = 0;
      }

      // ── RAG Memory Retrieval ──
      // When messages are dropped from context, search for relevant past memories
      // Skip retrieval for brand new chats to prevent old memories from interfering
      String memoriesBlock = '';

      final effectiveRagEnabled = _activeGroup != null
          ? groupRagEnabled
          : _storageService.memorySettings.ragEnabled;

      if (_isNewChat) {
        debugPrint(
          '[RAG:Chat] Skipping memory retrieval - new chat in progress',
        );
      } else if (droppedMessages > 0 &&
          _memoryService != null &&
          effectiveRagEnabled) {
        debugPrint(
          '[RAG:Chat] ── Prompt assembly: $droppedMessages messages dropped, triggering retrieval ──',
        );
        try {
          // Use last 3 messages as the query
          final queryMessages = _messages.reversed
              .take(3)
              .map((m) => '${m.sender}: ${m.displayText}')
              .join('\n');

          final sourceIds = await _getMemorySourceIds();
          debugPrint('[RAG:Chat] Memory source IDs: $sourceIds');

          final memories = await _memoryService!.retrieve(
            queryText: queryMessages,
            sourceCharacterIds: sourceIds,
            currentSessionId: _currentSessionId ?? '',
            inContextStart:
                droppedMessages, // only search messages that are out of context
            limit: groupRetrievalCount == 0 ? 9999 : groupRetrievalCount,
            characterPriorities: currentGroupRAGPriorities,
          );

          if (memories.isNotEmpty) {
            // Cap memory injection to the group's (or global) memory budget % of context.
            // The summary carries the weight of context compression; RAG only
            // supplements with specific details the summary missed. Too much
            // RAG (2500+ tokens) overwhelms the model and causes it to
            // reference stale events as if they're current ("going back in time").
            final contextSize = _storageService.backendSettings.contextSize;
            final budgetFraction = _activeGroup != null
                ? (groupMemoryBudgetPercent / 100.0)
                : 0.10;
            final memoryBudget = (contextSize * budgetFraction).round();
            final includedMemories = <String>[];
            int usedTokens = 0;
            for (final m in memories) {
              final memTokens = (m.content.length / 4).ceil();
              if (usedTokens + memTokens > memoryBudget &&
                  includedMemories.isNotEmpty) {
                debugPrint(
                  '[RAG:Chat] ⚠ Trimmed ${memories.length - includedMemories.length} memories to fit budget ($memoryBudget tokens)',
                );
                break;
              }
              usedTokens += memTokens;
              includedMemories.add('- ${m.content}');
            }
            if (includedMemories.isNotEmpty) {
              memoriesBlock =
                  '[Earlier in this conversation (already happened, do not revisit):\n${includedMemories.join('\n')}]\n';
              debugPrint(
                '[RAG:Chat] ✅ Injecting ${includedMemories.length}/${memories.length} memories (~$usedTokens tokens, budget: $memoryBudget)',
              );
            }
          } else {
            debugPrint('[RAG:Chat] No relevant memories found for this turn');
          }
        } catch (e) {
          debugPrint('[RAG:Chat] ✗ RAG retrieval failed: $e');
        }
      } else if (droppedMessages > 0 &&
          _storageService.memorySettings.ragEnabled) {
        debugPrint(
          '[RAG:Chat] ⚠ $droppedMessages messages dropped but RAG not operational (service=${_memoryService != null}, operational=${_memoryService?.isOperational ?? false})',
        );
      }

      // Realism injection was already computed above for budget

      // For chat APIs (OpenRouter, LM Studio), separate the system prompt
      // so it can be sent as a proper 'system' role message.
      final isRemoteApi = _llmProvider != null && !_llmProvider!.isLocal;
      final chatSystemPrompt = isRemoteApi
          ? "$systemPrompt\n$loreContent$personaBlock\n$userPersonaBlock"
                "Scenario: $scenario\n$mesExampleBlock"
          : null;

      final prompt = isRemoteApi
          ? "<START>\n"
                "$summaryBlock"
                "$memoriesBlock"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$objectiveBlock"
                "$realismBlock"
                "$needsCatastropheBlock"
                "$suffix"
                "$chanceTimeBlock"
          : "$systemPrompt\n"
                "$loreContent"
                "$personaBlock\n"
                "$userPersonaBlock"
                "Scenario: $scenario\n"
                "$mesExampleBlock"
                "<START>\n"
                "$summaryBlock"
                "$memoriesBlock"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$objectiveBlock"
                "$realismBlock"
                "$needsCatastropheBlock"
                "$suffix"
                "$chanceTimeBlock";

      // Track prompt budget for context viewer (always show full prompt)
      _lastAssembledPrompt = chatSystemPrompt != null
          ? '$chatSystemPrompt\n$prompt'
          : prompt;
      _lastPromptBudget = {
        'System Prompt': (systemPrompt.length / 4).ceil(),
        'Lorebook': (loreContent.length / 4).ceil(),
        'Persona': (personaBlock.length / 4).ceil(),
        'Scenario': ('Scenario: $scenario'.length / 4).ceil(),
        'Examples': (mesExampleBlock.length / 4).ceil(),
        'Summary': (summaryBlock.length / 4).ceil(),
        'Retrieved Memories': (memoriesBlock.length / 4).ceil(),
        'Chat History': (history.length / 4).ceil(),
        'Post-History': (postHistoryBlock.length / 4).ceil(),
        'Author\'s Note': (authorNoteBlock.length / 4).ceil(),
        'Objectives': (objectiveBlock.length / 4).ceil(),
        'Realism Mode': (realismBlock.length / 4).ceil(),
        if (needsCatastropheBlock.isNotEmpty)
          'Needs Catastrophe': (needsCatastropheBlock.length / 4).ceil(),
        if (droppedMessages > 0) 'Dropped Messages': droppedMessages,
      };
      // Remove zero-value entries
      _lastPromptBudget.removeWhere((_, v) => v == 0);

      // Stop sequences: include character names, and user name (except when impersonating)
      final g2 = _sessionGenSettings;
      final stopSequences = {
        ...g2.resolveStopSequences(_storageService).toSet(),
      };

      // In impersonate mode the model IS the user, so don't stop on user name
      if (mode != GenerationMode.impersonate) {
        stopSequences.add('\nUser:');
        stopSequences.add('\n${_userPersonaService.persona.name}:');
      }

      // For Continue mode, do *not* stop on the current speaker's name.
      // This lets the model produce long, natural extensions of the existing message
      // in that character's voice without the name stop cutting it off mid-continuation.
      // We still stop on other speakers or the user (to catch unwanted new turns).
      String? continueSpeakerName;
      if (mode == GenerationMode.continue_ && _messages.isNotEmpty && !_messages.last.isUser) {
        continueSpeakerName = _messages.last.sender;
      }

      if (_activeGroup != null) {
        for (final ch in _groupCharacters) {
          if (continueSpeakerName != null && ch.name == continueSpeakerName) continue;
          stopSequences.add('\n${ch.name}:');
        }
      } else {
        final cur = _activeCharacter!.name;
        if (continueSpeakerName == null || cur != continueSpeakerName) {
          stopSequences.add('\n$cur:');
        }
      }
      final stopList = stopSequences.toList();

      // Get the active LLM service (local or remote)
      final llmService =
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService;

      // For call mode with a dedicated call model, temporarily swap the model
      if (_callMode &&
          _storageService.sttSettings.callModelName.isNotEmpty &&
          _llmProvider != null &&
          !_llmProvider!.isLocal) {
        _originalModelName = _llmProvider!.openRouterService.modelName;
        _llmProvider!.openRouterService.configure(
          modelName: _storageService.sttSettings.callModelName,
        );
      }

      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
        maxLength: g2.resolveMaxLength(_storageService),
        minLength: g2.resolveMinLength(_storageService),
        minP: g2.resolveMinP(_storageService),
        temperature: g2.resolveTemperature(_storageService),
        repeatPenalty: g2.resolveRepeatPenalty(_storageService),
        repPenTokens: g2.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g2.resolveDynamicTempEnabled(_storageService)
            ? g2.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g2.resolveXtcThreshold(_storageService),
        xtcProbability: g2.resolveXtcProbability(_storageService),
        stopSequences: stopList,
        reasoningEnabled: (_callMode || mode == GenerationMode.continue_)
            ? false
            : g2.resolveReasoningEnabled(_storageService),
        reasoningEffort: g2.resolveReasoningEffort(_storageService),
        // Force zero thinking budget on Continue (and call mode) for providers like OpenRouter/Nano-GPT.
        // This tells supported models (Kimi K2 Thinking, DeepSeek hybrid reasoning models, certain Qwen3 etc.)
        // to spend 0 tokens on internal reasoning and answer directly, preventing the model from dumping
        // its next analysis/think block into the visible character response.
        reasoningMaxTokens: (_callMode || mode == GenerationMode.continue_) ? 0 : null,
        bannedPhrases: g2.resolveBannedPhrases(_storageService).isNotEmpty
            ? g2.resolveBannedPhrases(_storageService)
            : null,
      );

      // Get streaming response from whichever backend is active
      final stream = llmService.generateStream(genParams);

      // ── Phase: Prefilling ──
      // The HTTP request is now in flight. For KoboldCPP, the model is
      // processing the prompt (prefill/eval). No tokens arrive until
      // prefill finishes. Poll /api/extra/perf for real-time status.
      _generationPhase = GenerationPhase.prefilling;
      _prefillStartTime = DateTime.now();
      _prefillPromptTokens = (prompt.length / 4).ceil(); // Rough placeholder
      notifyListeners();

      // If using local KoboldCPP, poll /api/extra/perf during prefill
      // to get real prompt processing metrics.
      Timer? _perfPoller;
      final isLocalBackend = _llmProvider == null || _llmProvider!.isLocal;
      if (isLocalBackend) {
        // Get REAL token count from the model's tokenizer (async, updates UI when done)
        _koboldService.countTokens(prompt).then((realCount) {
          if (_generationPhase == GenerationPhase.prefilling && realCount > 0) {
            _prefillPromptTokens = realCount;
            debugPrint(
              '[Prefill] Actual token count from tokenizer: $realCount (was ~${(prompt.length / 4).ceil()} est)',
            );
            notifyListeners();
          }
        });

        _perfPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (_generationPhase != GenerationPhase.prefilling) {
            _perfPoller?.cancel();
            _perfPoller = null;
            return;
          }
          final perf = await _koboldService.fetchPerf();
          if (perf != null) {
            _lastPerfData = perf;
            notifyListeners();
          }
        });
      }

      String accumulatedResponse = "";
      bool stopFound = false;
      _tokenBuffer.clear();
      _displayedTokenCount = 0;
      _tokenTimestamps.clear();
      bool streamDone = false;
      DateTime? _thinkStartTime;
      bool _thinkStarted = false;
      bool _thinkEnded = false;

      // Determine message identity
      String originalText = '';
      String targetSender;
      bool isUserTarget;

      if (mode == GenerationMode.continue_) {
        originalText = _messages.last.text;
        targetSender = _messages.last.sender;
        isUserTarget = _messages.last.isUser;
        // Merge metadata if continuing
        if (_pendingRealismMetadata != null) {
          _messages.last.activeMetadata ??= {};
          _messages.last.activeMetadata!.addAll(_pendingRealismMetadata!);
          _pendingRealismMetadata = null;
        }
      } else {
        targetSender = mode == GenerationMode.normal
            ? speakingCharacter.name
            : _userPersonaService.persona.name;
        isUserTarget = mode == GenerationMode.impersonate;
        final initialMetadata = _pendingRealismMetadata != null
            ? Map<String, dynamic>.from(_pendingRealismMetadata!)
            : null;
        debugPrint(
          '[Realism:Metadata] Attaching to new message: bond_delta=${initialMetadata?['bond_delta']}, keys=${initialMetadata?.keys.toList()}',
        );
        _messages.add(
          ChatMessage(
            text: "",
            sender: targetSender,
            isUser: isUserTarget,
            characterId: mode == GenerationMode.normal
                ? _getCharacterIdForCard(speakingCharacter)
                : null,
            metadata: initialMetadata,
            swipeMetadata: initialMetadata != null ? [initialMetadata] : null,
          ),
        );
        _pendingRealismMetadata = null;
      }

      // Helper to update the visible message from buffer
      void _flushBufferToDisplay() {
        if (epoch != _generationEpoch) return; // stale generation
        if (_tokenBuffer.isEmpty && _displayedTokenCount == 0) return;
        // Build displayed text from all tokens up to _displayedTokenCount
        final displayTokens = _tokenBuffer.take(_displayedTokenCount).join();
        String displayText;
        if (mode == GenerationMode.continue_) {
          displayText = originalText + displayTokens;
        } else {
          displayText = displayTokens.trimLeft();
        }
        // CRITICAL: Modify existing message in place to preserve thinkingStartTime and other metadata
        _messages.last.text = displayText;
        notifyListeners();
      }

      // Read display buffer settings — disable for remote APIs (they're fast enough)
      final isRemoteBackend = _llmProvider != null && !_llmProvider!.isLocal;
      final bufferEnabled = isRemoteBackend
          ? false
          : _storageService.uiSettings.displayBufferEnabled;
      final targetTps = _storageService.uiSettings.targetDisplayTps;

      // Drain timer: displays tokens at the user-configured constant rate
      void _startDrainTimer() {
        if (_drainTimer != null) return;
        final interval = Duration(milliseconds: (1000.0 / targetTps).round());
        _drainTimer = Timer.periodic(interval, (_) {
          if (epoch != _generationEpoch) {
            _drainTimer?.cancel();
            _drainTimer = null;
            return;
          } // stale
          if (_displayedTokenCount < _tokenBuffer.length) {
            _displayedTokenCount++;
            _flushBufferToDisplay();
          } else if (streamDone) {
            // Stream finished and buffer fully drained
            _drainTimer?.cancel();
            _drainTimer = null;
          }
          // If buffer is caught up but stream still running, timer ticks idly until more tokens arrive
        });
      }

      // Consume the stream — tokens go into buffer (or display immediately)
      await for (final token in stream) {
        if (_cancelRequested) break;
        accumulatedResponse += token;
        _tokensGenerated++;
        _tokenTimestamps.add(DateTime.now());

        // ── Phase transition: first token marks end of prefill ──
        if (_tokensGenerated == 1) {
          _perfPoller?.cancel();
          _perfPoller = null;
          // Fetch final perf data so we know how long prefill really took
          if (isLocalBackend) {
            _koboldService.fetchPerf().then((perf) {
              if (perf != null) {
                _lastPerfData = perf;
              }
            });
          }
          _prefillStartTime = null;
        }

        // Broadcast token to external listeners (SSE bridge)
        _tokenBroadcast.add(token);
        _generationProgress = _maxTokens > 0
            ? (_tokensGenerated / _maxTokens).clamp(0.0, 1.0)
            : 0.0;

        // Sentence streaming: accumulate tokens and emit complete sentences
        _sentenceBuffer += token;

        // Split strategy:
        // 1. Always split at sentence boundaries: . ! ? followed by space, or \n
        // 2. For long buffers (>80 chars / ~15 words), also split at clause
        //    boundaries: ", " "; " " — " " - " to keep TTS chunks short (~1-3s)
        bool emitted = true;
        while (emitted) {
          emitted = false;

          // First try sentence boundaries
          final sentenceEnd = RegExp(r'[.!?]\s|[.!?]$|\n');
          if (sentenceEnd.hasMatch(_sentenceBuffer)) {
            final match = sentenceEnd.firstMatch(_sentenceBuffer)!;
            final sentence = _sentenceBuffer.substring(0, match.end).trim();
            _sentenceBuffer = _sentenceBuffer.substring(match.end);
            if (sentence.isNotEmpty) {
              _sentenceBroadcast.add(sentence);
              emitted = true;
            }
            continue;
          }

          // For long buffers, split at clause boundaries to keep TTS fast
          if (_sentenceBuffer.length > 80) {
            final clauseEnd = RegExp(r',\s|;\s|\s[—–-]\s');
            if (clauseEnd.hasMatch(_sentenceBuffer)) {
              // Find the LAST clause boundary to maximize chunk size
              Match? lastMatch;
              for (final m in clauseEnd.allMatches(_sentenceBuffer)) {
                if (m.start > 30) lastMatch = m; // at least 30 chars per chunk
              }
              if (lastMatch != null) {
                final chunk = _sentenceBuffer
                    .substring(0, lastMatch.end)
                    .trim();
                _sentenceBuffer = _sentenceBuffer.substring(lastMatch.end);
                if (chunk.isNotEmpty) {
                  _sentenceBroadcast.add(chunk);
                  emitted = true;
                }
              }
            }
          }
        }

        // Client-side safety trim check (mid-stream)
        for (final stop in stopList) {
          if (accumulatedResponse.contains(stop)) {
            int index = accumulatedResponse.indexOf(stop);
            final trimmedTotal = accumulatedResponse.substring(0, index);
            final previousTotal = _tokenBuffer.join();
            final lastTokenContribution = trimmedTotal.substring(
              previousTotal.length.clamp(0, trimmedTotal.length),
            );
            if (lastTokenContribution.isNotEmpty) {
              _tokenBuffer.add(lastTokenContribution);
            }
            accumulatedResponse = trimmedTotal;
            stopFound = true;
            break;
          }
        }

        if (!stopFound) {
          _tokenBuffer.add(token);
        }

        // Track think timing
        if (!_thinkStarted && accumulatedResponse.contains('<think>')) {
          _thinkStarted = true;
          _thinkStartTime = DateTime.now();
          _generationPhase = GenerationPhase.thinking;
          if (_messages.isNotEmpty) {
            _messages.last.thinkingStartTime =
                _thinkStartTime.millisecondsSinceEpoch;
          }
        }
        if (_thinkStarted &&
            !_thinkEnded &&
            accumulatedResponse.contains('</think>')) {
          _thinkEnded = true;
          // Transition out of thinking to buffering/generating
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
          if (_thinkStartTime != null && _messages.isNotEmpty) {
            _messages.last.thinkingDurationMs = DateTime.now()
                .difference(_thinkStartTime)
                .inMilliseconds;
            // Keep thinkingStartTime for fallback display logic in UI
          }
        }
        // If no thinking involved, first token transitions directly
        if (!_thinkStarted && _tokensGenerated == 1) {
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
        }

        if (bufferEnabled) {
          // Calculate current rolling TPS (last 3 seconds)
          final now = DateTime.now();
          final cutoff = now.subtract(const Duration(seconds: 3));
          final recentCount = _tokenTimestamps
              .where((t) => t.isAfter(cutoff))
              .length;
          final windowStart =
              _tokenTimestamps.where((t) => t.isAfter(cutoff)).firstOrNull ??
              _generationStartTime!;
          final windowElapsed =
              now.difference(windowStart).inMilliseconds / 1000.0;
          final currentTps = (recentCount >= 2 && windowElapsed > 0)
              ? recentCount / windowElapsed
              : (_tokensGenerated > 0
                    ? _tokensGenerated /
                          (now
                                  .difference(_generationStartTime!)
                                  .inMilliseconds /
                              1000.0)
                    : 0.0);

          if (_drainTimer == null && _tokensGenerated >= 10) {
            // Not yet draining — calculate when to start
            // Buffer target = how many tokens fill the configured duration
            final bufferDuration =
                _storageService.uiSettings.bufferDurationSeconds;
            int bufferTarget;
            if (currentTps > 0) {
              bufferTarget = (currentTps * bufferDuration).round().clamp(
                5,
                _maxTokens,
              );
            } else {
              bufferTarget = 30; // Fallback if TPS unknown
            }

            if (_tokenBuffer.length >= bufferTarget) {
              _isBuffering = false;
              _generationPhase = GenerationPhase.generating;
              _startDrainTimer();
            }
          } else if (_drainTimer != null) {
            // Already draining — check if buffer is running low
            final remaining = _tokenBuffer.length - _displayedTokenCount;
            if (remaining <= 3 && !streamDone) {
              // Buffer critically low — pause drain to rebuild
              _drainTimer?.cancel();
              _drainTimer = null;
              _isBuffering = true;
              _generationPhase = GenerationPhase.buffering;
            }
          }
        } else {
          // No buffer: display tokens immediately
          _isBuffering = false;
          _generationPhase = GenerationPhase.generating;
          _displayedTokenCount = _tokenBuffer.length;
          _flushBufferToDisplay();
        }

        // Update TPS/progress in the bar even during buffering
        notifyListeners();

        if (stopFound) break;
      }

      // Mark stream as done
      streamDone = true;
      _isBuffering = false;

      if (!bufferEnabled) {
        // No buffer: everything already displayed
        _displayedTokenCount = _tokenBuffer.length;
        _flushBufferToDisplay();
      } else if (_drainTimer == null) {
        // Buffer never started draining (genTps < targetTps) — start now with all tokens ready
        _startDrainTimer();
        // Wait for drain to complete
        while (_displayedTokenCount < _tokenBuffer.length) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      } else {
        // Drain already running — wait for it to finish
        while (_displayedTokenCount < _tokenBuffer.length) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      }

      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;
      _perfPoller?.cancel();
      _perfPoller = null;

      // Fetch final perf stats from KoboldCPP for post-generation display
      if (isLocalBackend) {
        _koboldService.fetchPerf().then((perf) {
          if (perf != null) _lastPerfData = perf;
        });
      }

      // Signal generation complete to SSE listeners
      _tokenBroadcast.add('__DONE__');

      // Flush remaining sentence buffer and signal done to sentence listeners
      if (_sentenceBuffer.trim().isNotEmpty) {
        _sentenceBroadcast.add(_sentenceBuffer.trim());
        _sentenceBuffer = '';
      }
      _sentenceBroadcast.add('__DONE__');

      notifyListeners();

      // Only finalize if this generation is still current
      if (epoch == _generationEpoch) {
        String finalResponse = accumulatedResponse.trim();

        // SillyTavern-like safety net for Continue (and call mode): even after requesting
        // enabled:false + max_tokens:0 + exclude:true on the provider, some thinking models
        // (Kimi 2.6:thinking etc.) can still emit stray <think> or reasoning text.
        // Strip it from the final text before it becomes part of the character's message.
        // This matches ST's "Strip Reasoning Tags" behavior as a client-side backstop.
        if (mode == GenerationMode.continue_ || _callMode) {
          finalResponse = _stripThinkBlocks(finalResponse);
        }

        // Snapshot which entries were already triggered before scanning the AI response.
        // We will only decrement those — newly AI-triggered entries must keep their
        // full depth budget so they are visible on the next user turn.
        final preAiTriggered = <LorebookEntry>{};
        final charactersForSnapshot = _activeGroup != null
            ? _groupCharacters
            : (_activeCharacter != null
                  ? [_activeCharacter!]
                  : <CharacterCard>[]);
        for (final ch in charactersForSnapshot) {
          if (ch.lorebook != null) {
            for (final e in ch.lorebook!.entries) {
              if (e.isTriggered && !e.constant) preAiTriggered.add(e);
            }
          }
          for (final worldName in ch.worldNames) {
            final world = _worldRepository.worlds
                .where((w) => w.name == worldName)
                .firstOrNull;
            if (world == null) continue;
            for (final e in world.lorebook.entries) {
              if (e.isTriggered && !e.constant) preAiTriggered.add(e);
            }
          }
        }

        if (finalResponse.isNotEmpty) {
          _lorebookScanner.scanLorebook(finalResponse);
        }

        // Decrement only entries that were active before the AI response.
        // This preserves full depth for lore discovered in the AI's own words.
        // Thin delegation (preAi set computed in god for snapshot; scanner owns decrement).
        _lorebookScanner.decrementLoreDepthForEntries(preAiTriggered);

        // Save session after AI message is complete
        await _saveChat();

        // Phase 2: Update hidden inter-character feelings for the speaker who
        // just responded, based on what was said in the recent exchange.
        // This makes the invisible tracking react to actual dialogue.
        if (_activeGroup != null &&
            !_observerMode &&
            finalResponse.isNotEmpty) {
          final lastSpeaker = _messages.isNotEmpty ? _messages.last.sender : '';
          final speakerCard = _groupCharacters.firstWhere(
            (c) => c.name == lastSpeaker,
            orElse: () => _groupCharacters.first,
          );
          final speakerId = _getCharacterIdFromCard(speakerCard);
          if (speakerId.isNotEmpty) {
            _relationshipService.updateInterCharacterFeelingsFromRecentExchange(
              speakerId,
            );
            // (old checkpoint call removed in v30) // persist the hidden relationship changes
          }
        }

        // For group non-observer turns, temporarily re-impersonate the speaker of the *just generated*
        // response so the post-gen needs checks (now _runPostGenNeedsChecks thin to
        // _needsImpactEvaluator) use the correct _activeCharacter (for name, personality/stance
        // in the consolidated needs impact prompt). The pre-speaker-eval left the *scalars*
        // (incl. needs vector) loaded for this speaker but restored the _activeCharacter pointer
        // to the prior speaker; the thin delegate relies on the pointer for cbs. We restore the
        // pointer after the checks (scalars remain correct for the persist below).
        CharacterCard? prePostActiveChar;
        if (_activeGroup != null && !_observerMode) {
          prePostActiveChar = _activeCharacter;
          _activeCharacter = speakingCharacter;
          final sid = _getCharacterIdFromCard(speakingCharacter);
          if (sid.isNotEmpty) {
            _loadGroupRealismIntoScalars(sid);
          }
        }

        await _runPostGenNeedsChecks(finalResponse);

        if (prePostActiveChar != null) {
          _activeCharacter = prePostActiveChar;
        }

        // For group non-observer, persist the post-scene + long-gen-decay needs changes (and any
        // other scalars mutated by the checks) back into _groupRealism for this speaker. This is
        // what makes sidebar member cards + getNeedsForGroupCharacter() + future loads see the
        // effects of the just-generated response. (Pre-eval saved the pre-turn state for bond/etc;
        // this captures the *response* effects on needs.)
        if (_activeGroup != null &&
            !_observerMode &&
            finalResponse.isNotEmpty &&
            _messages.isNotEmpty) {
          final lastSender = _messages.last.sender;
          final speakerCard = _groupCharacters.firstWhere(
            (c) => c.name == lastSender,
            orElse: () => _groupCharacters.first,
          );
          final sid = _getCharacterIdFromCard(speakerCard);
          if (sid.isNotEmpty) {
            _saveScalarsIntoGroupRealism(sid);
          }
        }

        // Check if summary needs updating (fire-and-forget)
        // Group name resolution for {{char}} in summary prompt is best-effort at trigger time (after prePostActiveChar restore dance); correct for 1:1, may use restored active or group fallback in group non-obs (timing-dependent per group impersonation; dispatch preserved via cbs). See leaf header + test for qualify.
        _maybeUpdateSummary();

        // Embed messages for RAG memory (fire-and-forget)
        _maybeEmbedMessages();

        // Periodic evaluations: extract user facts + evolve character personality
        // Both run on the same cadence (every N user messages), sequentially.
        _maybeRunPeriodicEvals();

        // (Task completion check now runs pre-generation in sendMessage)

        // TTS auto-play: speak the new character message automatically
        if (_ttsService != null &&
            _storageService.ttsSettings.ttsEnabled &&
            _storageService.ttsSettings.ttsAutoPlay &&
            _messages.isNotEmpty &&
            !_messages.last.isUser) {
          final lastMsg = _messages.last;
          final msgId = 'msg_${_messages.length - 1}';
          // Resolve per-character voice, falling back to global default
          String? voiceKey;
          if (_activeGroup != null) {
            final charMatch = _groupCharacters
                .where((c) => c.name == lastMsg.sender)
                .firstOrNull;
            voiceKey = charMatch?.ttsVoice;
          } else {
            voiceKey = _activeCharacter?.ttsVoice;
          }
          _ttsService!.speak(
            lastMsg.displayText,
            voiceKey: voiceKey,
            messageId: msgId,
          );
        }

        // Auto-play: if director mode is active, queue the next character
        if (_autoPlayActive && _observerMode && _activeGroup != null) {
          // If TTS is active, wait for it to finish before starting the delay
          if (_ttsService != null && _ttsService!.isSpeaking) {
            _waitForTtsThenContinue();
          } else {
            final delayMs = (directorDelaySec * 1000).round();
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_autoPlayActive && !_isGenerating) {
                _autoPlayNext();
              }
            });
          }
        }
      }

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }
    } catch (e) {
      final wasCancelled = _cancelRequested;
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final errStr = e.toString();
      final isConnectionClosed =
          errStr.contains('Connection closed before full header') ||
          errStr.contains('Connection refused') ||
          errStr.contains('errno = 61') || // macOS ECONNREFUSED
          errStr.contains('SocketException') ||
          (errStr.contains('ClientException') && errStr.contains('closed'));
      final treatAsCancel = wasCancelled || isConnectionClosed;

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
        if (_originalModelName != null && _llmProvider != null) {
          _llmProvider!.openRouterService.configure(
            modelName: _originalModelName,
          );
        }

        // Save the partial response so regen/continue work
        await _saveChat();
        notifyListeners();
        return;
      }

      // Build user-friendly error message
      String errorMsg = e.toString();
      // Strip Dart's "Exception: " prefix for cleaner display
      errorMsg = errorMsg.replaceFirst(RegExp(r'^Exception:\s*'), '');

      if (errorMsg.contains('STREAMING_NOT_SUPPORTED') ||
          errorMsg.contains('HTTP 405')) {
        errorMsg =
            'HTTP 405: The server does not support this request. '
            'If streaming is enabled, try disabling it in Settings > Generation Settings. '
            'Also verify your API URL is correct.';
      } else if (errorMsg.contains('Backend process crashed')) {
        errorMsg =
            'The backend crashed (likely out of VRAM). '
            'Try reducing GPU layers or context size in Settings.';
      } else if (errorMsg.contains('timed out') ||
          errorMsg.contains('TimeoutException')) {
        errorMsg =
            'Request timed out. The model may be too large or the server too slow.';
      } else if (errorMsg.contains('Connection closed before full header') ||
          (errorMsg.contains('ClientException') &&
              errorMsg.contains('closed'))) {
        errorMsg =
            'The connection to the backend was closed unexpectedly. '
            'The model may still be loading — wait for the green ready indicator and try again. '
            'If this persists, the backend may have run out of VRAM.';
      }

      _messages.add(
        ChatMessage(text: errorMsg, sender: "System", isUser: false),
      );

      // Signal error to SSE listeners
      _tokenBroadcast.add('__ERROR__');

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }

      notifyListeners();
    }
  }

  String _buildChatHistory() {
    final lines = _messages.map((m) {
      // Director notes get bracketed so the AI treats them as instructions
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();
    return lines.join("\n");
  }

  /// Build chat history that fits within a token budget.
  /// Walks messages newest-to-oldest, dropping the oldest that don't fit.
  /// Returns ({String history, int droppedCount, int tokenCount}).
  Future<({String history, int droppedCount, int tokenCount})>
  _buildChatHistoryWithBudget(int tokenBudget) async {
    if (_messages.isEmpty) return (history: '', droppedCount: 0, tokenCount: 0);

    // Format all messages, skipping hidden group realism checkpoints
    final formatted = _messages.map((m) {
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();

    // If budget is very large or negative (unlimited), return everything
    if (tokenBudget <= 0) {
      return (history: formatted.join('\n'), droppedCount: 0, tokenCount: 0);
    }

    // Walk from newest to oldest, accumulating messages that fit
    final included = <String>[];
    int usedTokens = 0;
    int droppedCount = 0;

    for (int i = formatted.length - 1; i >= 0; i--) {
      final msgText = formatted[i];
      final msgTokens = await _countTokens(msgText);
      if (usedTokens + msgTokens > tokenBudget && included.isNotEmpty) {
        // This message would exceed budget — drop it and all older messages
        droppedCount = i + 1;
        break;
      }
      usedTokens += msgTokens;
      included.insert(0, msgText);
    }

    // If messages were dropped, prepend a separator
    String history = included.join('\n');
    if (droppedCount > 0) {
      history =
          '[Earlier messages truncated — see summary above for context]\n$history';
    }

    return (
      history: history,
      droppedCount: droppedCount,
      tokenCount: usedTokens,
    );
  }

  /// Count tokens for a text string. Uses KoboldCpp's tokenizer when available,
  /// falls back to chars/4 estimate for remote APIs.
  Future<int> _countTokens(String text) async {
    if (text.isEmpty) return 0;
    // Use the KoboldCpp tokenizer if we're running locally
    if (_llmProvider == null || _llmProvider!.isLocal) {
      return _koboldService.countTokens(text);
    }
    // Fallback for remote APIs
    return (text.length / 4).ceil();
  }

  /// Reload the current session from the database without clearing messages first.
  /// Used after cloud sync or DB migration updates the database — preserves the
  /// user's active chat instead of wiping it.
  Future<void> reloadCurrentSession() async {
    if (_currentSessionId == null) return;
    debugPrint(
      '[ChatService] 🔄 reloadCurrentSession: reloading session $_currentSessionId '
      '(currently ${_messages.length} messages in memory)',
    );
    await loadSession(_currentSessionId!);
  }

  void clearChat() async {
    debugPrint(
      '[ChatService] 🟡 clearChat: clearing ${_messages.length} messages',
    );
    _messages.clear();
    await _saveChat();
    notifyListeners();
  }

  /// Delete a specific chat session and its messages.
  /// If it's the current session, switches to the most recent remaining one.
  Future<void> deleteSession(String sessionId) async {
    await _db.deleteMessagesForSession(sessionId);
    await _db.deleteSessionById(sessionId);

    // If we deleted the current session, switch to another
    if (sessionId == _currentSessionId) {
      final remaining = await getSessions();
      if (remaining.isNotEmpty) {
        await loadSession(remaining.first['id']);
      } else {
        // No sessions left — start fresh
        debugPrint(
          '[ChatService] 🟡 deleteSession: no sessions left, clearing messages',
        );
        _messages.clear();
        _currentSessionId = null;
        await startNewChat();
      }
    }
    notifyListeners();
  }

  void deleteMessage(int index) async {
    if (index >= 0 && index < _messages.length) {
      _messages.removeAt(index);

      // Time-travel rollback for realism when deleting a character message.
      // Restore from the new last message if it has a snapshot, regardless
      // of whether this was the last message. This ensures needs state
      // (and all realism fields) reset to their previous saved values.
      if (_messages.isNotEmpty) {
        final newLast = _messages.last;
        _restoreRealismStateFromMessage(newLast);
      }

      await _saveChat();
      notifyListeners();
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      _cancelRequested = true;
      // Abort the in-flight HTTP request so we don't have to wait for the next token
      (testLlmServiceOverride ?? _llmProvider?.activeService)
          ?.abortGeneration();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> _cancelAndWaitForGeneration() async {
    if (!_isGenerating) return;
    _cancelRequested = true;
    // Spin until _generateResponse finishes its cleanup
    while (_isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void editMessage(int index, String newText) async {
    if (index >= 0 && index < _messages.length) {
      final msg = _messages[index];
      // Use the text setter so we only update the current swipe's text
      // while preserving all realism metadata, swipes, swipeMetadata, durations, etc.
      // This prevents chips (needs_deltas, bond/trust deltas, emotion, etc.) from disappearing on edit.
      msg.text = newText;
      await _saveChat();
      notifyListeners();
    }
  }

  // ── Summary System ──────────────────────────────────────────────────

  /// Manually set the summary text.
  void setSummary(String text) {
    _summary = text;
    _saveChat();
    notifyListeners();
  }

  /// Pause or resume automatic summary updates.
  void setSummaryPaused(bool paused) {
    _summaryPaused = paused;
    notifyListeners();
  }

  /// Force an immediate summary regeneration.
  // Thin delegation / coord (full generate in summary_service step 12; flag/cadence
  // /paused/enabled stay thin in god per plan; "thin delegation here; full summary in step 12").
  Future<void> forceSummaryUpdate() async {
    if (_isSummaryGenerating) return;
    await _generateSummaryInBackground();
  }

  /// Check if a summary update is needed and trigger it non-blockingly.
  // Thin delegation / coord (cadence count + guards here; full _generate + prompt/RAG/strip
  // in summary_service step 12; "thin delegation here; full summary in step 12").
  void _maybeUpdateSummary() {
    if (!_storageService.memorySettings.summaryEnabled) return;
    if (_summaryPaused) return;
    if (_isSummaryGenerating) return;
    if (_llmProvider == null) return;

    // Count user messages since last summary update
    int userMessagesSinceSummary = 0;
    for (int i = _summaryLastIndex; i < _messages.length; i++) {
      if (_messages[i].isUser) userMessagesSinceSummary++;
    }

    if (userMessagesSinceSummary >=
        _storageService.memorySettings.summaryInterval) {
      // Fire and forget — don't await
      _generateSummaryInBackground();
    }
  }

  /// Embed message windows for RAG memory retrieval (fire-and-forget).
  /// Called after each generation completes. Only embeds new windows that
  /// haven't been embedded yet.
  void _maybeEmbedMessages() {
    if (_memoryService == null || !_storageService.memorySettings.ragEnabled) {
      return;
    }
    if (_currentSessionId == null) return;
    if (_messages.length < _storageService.memorySettings.ragWindowSize) return;

    final characterId = _getCharacterId();

    // Format messages for embedding (skip hidden group state checkpoints)
    final formatted = _messages.map((m) {
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();

    debugPrint(
      '[RAG:Chat] ▶ Triggering background embedding (session: $_currentSessionId, char: $characterId, ${formatted.length} msgs)',
    );

    // Fire and forget — don't await
    _memoryService!.embedMessageWindow(
      sessionId: _currentSessionId!,
      characterId: characterId,
      formattedMessages: formatted,
      totalMessageCount: _messages.length,
    );
  }

  // ── Action Suggestions ────────────────────────────────────────────────

  /// Clear suggestions (called when user sends any message).
  void clearSuggestions() {
    if (_suggestedActions.isNotEmpty || _isGeneratingActions) {
      _suggestedActions = [];
      _isGeneratingActions = false;
      notifyListeners();
    }
  }

  /// Generate action suggestions on demand (called from UI button).
  Future<void> generateActions() async {
    if (_isGeneratingActions) return;
    if (_llmProvider == null) return;
    if (_messages.isEmpty) return;

    _isGeneratingActions = true;
    _suggestedActions = [];
    notifyListeners();

    try {
      final llmService = _llmProvider!.activeService;
      if (!llmService.isReady) {
        debugPrint('[Actions] ✗ LLM not ready');
        return;
      }

      // Build context from recent messages (last 6)
      final recentMessages = _messages.length > 6
          ? _messages.sublist(_messages.length - 6)
          : _messages;

      final contextText = recentMessages
          .map((m) {
            return '${m.sender}: ${m.text}';
          })
          .join('\n');

      final userName = _userPersonaService.persona.name;

      final prompt =
          'Suggest 4 short actions $userName could do next. '
          'Each action must be a BRIEF LABEL (5-10 words max) describing what to do, NOT a full response. '
          'Think of these as button labels or menu items.\n\n'
          'Examples of GOOD actions:\n'
          '1. Kiss her and pull her closer\n'
          '2. Ask about her day at work\n'
          '3. Tease her by pulling away\n'
          '4. Suggest moving somewhere private\n\n'
          'Examples of BAD actions (too long, too detailed):\n'
          '1. *I lean in and press my lips against hers, tasting...*\n\n'
          'Recent conversation:\n$contextText\n\n'
          'Write 4 short action labels for $userName (numbered 1-4, one per line):';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 300,
        temperature: 0.8,
        stopSequences: ['\n\n\n'],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }
      responseText = responseText.trim();

      debugPrint('[Actions] Raw response:\n$responseText');

      // Parse numbered list: "1. Action", "-", "*", or bullet
      final lines = responseText.split('\n');
      var actions = <String>[];

      for (final line in lines) {
        var cleanLine = line
            .trim()
            .replaceAll(RegExp(r'^\*+|\*+$|^_+|_+$'), '')
            .trim();
        final match = RegExp(
          r'^\s*(?:\d+[\.\)]|[-*•]|)\s*(.+)$',
        ).firstMatch(cleanLine);
        if (match != null) {
          final action = match.group(1)!.trim().replaceAll(RegExp(r'\*$'), '');
          // Ignore conversational filler lines
          if (action.isNotEmpty &&
              !action.toLowerCase().contains('here are') &&
              !action.endsWith(':')) {
            actions.add(action);
          }
        }
      }

      // Fallback if LLM just output raw lines
      if (actions.isEmpty) {
        for (final line in lines) {
          final cleanLine = line.trim();
          if (cleanLine.isNotEmpty &&
              !cleanLine.endsWith(':') &&
              !cleanLine.toLowerCase().contains('here are')) {
            actions.add(cleanLine);
          }
        }
      }

      if (actions.isNotEmpty) {
        _suggestedActions = actions.take(6).toList(); // cap at 6
        debugPrint(
          '[Actions] ✅ Generated ${_suggestedActions.length} suggestions',
        );
      } else {
        debugPrint('[Actions] ✗ Could not parse any actions from response');
      }
    } catch (e) {
      debugPrint('[Actions] ✗ Generation failed: $e');
    } finally {
      _isGeneratingActions = false;
      notifyListeners();
    }
  }

  // ── Objective System ───────────────────────────────────────────────────

  /// Load the active objectives for the current session from DB.
  Future<void> _loadActiveObjectives() async {
    if (_activeCharacter == null || _currentSessionId == null) {
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion = false;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadActiveObjectives empty hygiene)
      _isSummaryGenerating =
          false; // secondary zero in _loadActiveObjectives empty (0-session hygiene for summary flag)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero in _loadActiveObjectives empty (0-session hygiene; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero in _loadActiveObjectives empty (0-session hygiene; evolution_service (stateless or prompt-only; no reset calls needed))
      return;
    }
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    try {
      _activeObjectives = await _db.getActiveObjectives(
        charId,
        chatId: _currentSessionId!,
      );
      for (final obj in _activeObjectives) {
        debugPrint(
          '[Objective] Loaded: ${obj.objective} (Primary: ${obj.isPrimary})',
        );
      }
    } catch (e) {
      debugPrint(
        '[Objective] Failed to load (will run without objectives this session): $e',
      );
      _activeObjectives = [];
    }
    notifyListeners(); // Central _disposed guard in ChatService overrides now protects this (and all other) post-async notify sites. Per-site try/catch removed (deletion part of rec 2 task); see god _disposed + notify override + setActiveCharacter:2205 comment.
  }

  /// Build the prompt injection text for the active objectives.
  /// Wording intensity varies based on injection depth for the primary objective.
  /// Secondary objectives are injected as ambient background goals.
  String _getObjectiveInjection() {
    // Thin delegation (full in AuthorNoteBuilder per step 8). Objective state mgmt
    // (lists, getters, tasksFor) stays in god (objective_service is later step).
    return _authorNoteBuilder.buildObjectiveInjection();
  }

  /// Set a new objective for the current session (or for a specific character when in group mode).
  ///
  /// [autoGenerateTasks] defaults to false. User-created objectives (typed in the UI) should
  /// not auto-generate subtasks — the user is in control of their own quests and can use the
  /// explicit "Generate Tasks" button if desired.
  ///
  /// Autonomous objectives proposed by the character (via the realism "proposed_objective"
  /// evals) pass true so that the character's self-generated goals come with concrete
  /// sequential tasks. This makes the AI-driven objectives feel organic and like something
  /// the character is actively striving to accomplish.
  Future<void> setObjective(
    String goal, {
    bool isPrimary = true,
    CharacterCard? targetCharacter,
    bool autoGenerateTasks = false,
  }) async {
    if (goal.trim().isEmpty) return;
    if (_currentSessionId == null) return;

    CharacterCard? target = targetCharacter;
    if (target == null) {
      if (_activeGroup != null) {
        // During per-speaker group realism evals (which propose autonomous objectives),
        // _activeCharacter is temporarily impersonated to the evaluated speaker. Prefer it
        // so the character's own internal goal attaches to *them*, not nextCharacter.
        final currentIsGroupMember =
            _activeCharacter != null &&
            _groupCharacters.any(
              (c) =>
                  _getCharacterIdFromCard(c) ==
                  _getCharacterIdFromCard(_activeCharacter!),
            );
        if (currentIsGroupMember) {
          target = _activeCharacter;
        } else {
          target = nextCharacter ?? _groupCharacters.firstOrNull;
        }
      } else {
        target = _activeCharacter;
      }
    }
    if (target == null) return;

    final charId = _getCharacterIdFromCard(target);

    if (isPrimary) {
      final existing = await _db.getObjectivesForCharacter(
        charId,
        chatId: _currentSessionId,
      );
      for (final obj in existing) {
        if (obj.active && obj.isPrimary) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(obj.id),
              isPrimary: const drift.Value(false),
            ),
          );
        }
      }
    } else {
      final currentSecondaries = secondaryObjectives;
      if (currentSecondaries.length >= 2) {
        for (int i = 0; i < currentSecondaries.length - 1; i++) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(currentSecondaries[i].id),
              active: const drift.Value(false),
            ),
          );
        }
      }
    }

    final newId = const Uuid().v4();
    await _db.insertObjective(
      ObjectivesCompanion.insert(
        id: newId,
        characterId: charId,
        objective: goal.trim(),
        chatId: drift.Value(_currentSessionId),
        active: const drift.Value(true),
        isPrimary: drift.Value(isPrimary),
      ),
    );

    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;

    if (autoGenerateTasks) {
      try {
        final forChar = await getActiveObjectivesFor(target);
        final matches = forChar.where((o) => o.id == newId);
        final addedObj = matches.isNotEmpty ? matches.first : null;
        if (addedObj != null) {
          unawaited(
            generateObjectiveTasks(
              addedObj,
              taskCount: 3,
              nsfw: false,
            ), // step 11 thin (full in objective_proposal)
          );
        }
      } catch (_) {
        // Objective created successfully; task generation is best-effort and non-fatal.
        // User can always tap "Generate Tasks" manually.
      }
    }
  }

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  // Thin delegation (full generateObjectiveTasks + 2000 budget + central strip + proposal
  // handling in objective_proposal step 11; objective mgmt coordination / list / load / db
  // updates stayed thin in god per plan for step9/11; "thin delegation here; full objective
  // proposal in step 11").
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) => _objectiveProposal.generateObjectiveTasks(
    obj,
    taskCount: taskCount,
    nsfw: nsfw,
  );

  /// Marks the first uncompleted task matching taskDesc as completed (best-effort side-effect
  /// for auto-complete in checkTaskCompletionInBackground currentTask YES path).
  /// (Thin delegation; full mutation logic here in god per plan for step 11 to keep list/db
  /// mutation thin/stayed in god; leaf calls via cb. Matches toggleTask pattern exactly.)
  Future<void> markTaskCompleted(Objective obj, String taskDesc) async {
    final tasks = tasksForObjective(obj);
    final idx = tasks.indexWhere(
      (t) => (t['description'] as String) == taskDesc && t['completed'] != true,
    );
    if (idx < 0) return;
    tasks[idx]['completed'] = true;
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Manually toggle a task's completion status.
  Future<void> toggleTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;

    tasks[taskIndex]['completed'] = !(tasks[taskIndex]['completed'] as bool);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update the description of a specific task.
  Future<void> updateTask(
    Objective obj,
    int taskIndex,
    String newDescription,
  ) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    if (newDescription.trim().isEmpty) return;

    tasks[taskIndex]['description'] = newDescription.trim();
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Clear the active objective.
  Future<void> clearObjective(Objective obj) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        active: const drift.Value(false),
      ),
    );
    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;
  }

  /// Update the injection depth for the active objective.
  Future<void> updateObjectiveDepth(Objective obj, int depth) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        injectionDepth: drift.Value(depth),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Add a manually created task to the active objective.
  Future<void> addManualTask(Objective obj, String description) async {
    if (description.trim().isEmpty) return;
    final tasks = tasksForObjective(obj);
    tasks.add({'description': description.trim(), 'completed': false});
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Remove a task from the active objective.
  Future<void> removeTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks.removeAt(taskIndex);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update how often task completion is checked.
  Future<void> updateCheckFrequency(Objective obj, int frequency) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        checkFrequency: drift.Value(frequency),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Check if the current task has been completed (called periodically).
  /// Manually trigger a completion check (called from UI "Check now" button).
  void forceCheckCompletion() {
    if (_activeObjectives.isEmpty) return;
    _checkTaskCompletionInBackground(); // step 11 thin (full in objective_proposal)
    notifyListeners(); // trigger UI to show spinner
  }

  /// Whether a completion check is currently running.
  bool get isCheckingCompletion => _isCheckingCompletion;

  /// Synchronous version — awaits the check. Used pre-generation.
  Future<void> _maybeCheckTaskCompletionSync() async {
    if (_activeObjectives.isEmpty ||
        _llmProvider == null ||
        _isCheckingCompletion) {
      return;
    }

    _messagesSinceLastCheck++;
    final freq = _realismEnabled
        ? 1
        : (primaryObjective?.checkFrequency ??
              _activeObjectives.first.checkFrequency);
    if (_messagesSinceLastCheck < freq) return;
    _messagesSinceLastCheck = 0;

    await _checkTaskCompletionInBackground(); // step 11 thin (full in objective_proposal)
  }

  // Thin delegation (full _checkTaskCompletionInBackground + 2000 budget + central strip in
  // objective_proposal step 11; objective mgmt coordination / isChecking flag / load / db
  // updates stayed thin in god per plan for step9/11; "thin delegation here; full objective
  // proposal in step 11").
  Future<void> _checkTaskCompletionInBackground() =>
      _objectiveProposal.checkTaskCompletionInBackground();

  int _userMessagesSinceLastPeriodicEval = 0;
  bool _isExtractingFacts =
      false; // secondary runtime flag (transient guard for fact extraction leaf); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths to prevent leak of in-flight state across contexts (see CLAUDE.md "keep reset blocks in sync" + "incomplete zeroing..." (leaves incl fact/evo/verif + needs_impact etc)). The counter must likewise be zeroed on those paths (prevents stale/early trigger after context switch).

  /// Unified periodic evaluation: runs fact extraction + character evolution
  /// sequentially on the same cadence (every N user messages).
  // Thin delegation / coord (cadence count + guards + auto*Enabled/Interval/llmProvider
  // here; full _extractFactsInBackground + quality/consolidate + prompt/LLM/stream/JSON/gate
  // in fact_extraction step 13 ("thin delegation here; full fact extraction in step 13");
  // evolution trigger in evolution_service step 14 ("thin delegation here; full character
  // evolution in step 14")).
  void _maybeRunPeriodicEvals() {
    final autoPersona = _storageService.memorySettings.autoPersonaEnabled;
    final autoEvolution =
        _storageService.memorySettings.characterEvolutionEnabled;
    if (!autoPersona && !autoEvolution) return;
    if (_llmProvider == null) return;
    if (_isExtractingFacts || _isEvolvingCharacter) return;

    // Note: this path is *not* gated on !_observerMode.
    // Character evolution is deliberately allowed in Director Mode (see
    // _triggerCharacterEvolution for rationale). Realism/Needs simulation is
    // the only system that pauses in Director Mode.

    _userMessagesSinceLastPeriodicEval++;
    if (_userMessagesSinceLastPeriodicEval <
        _storageService.memorySettings.autoPersonaInterval) {
      return;
    }
    _userMessagesSinceLastPeriodicEval = 0;

    debugPrint(
      '[Periodic] ▶ Triggering periodic evals (every ${_storageService.memorySettings.autoPersonaInterval} user messages)',
    );
    _runPeriodicEvalsInSequence();
  }

  /// Run fact extraction first, then character evolution, sequentially.
  // Thin delegation / coord (if autoPersonaEnabled guard + debug + await _extract call here;
  // full extract + consolidate + gate in fact_extraction step 13; "thin delegation here;
  // full fact extraction in step 13"). Evolution: if enabled guard + debug + _trigger thin here;
  // full trigger/extract/LLM/persist/layering in evolution_service step 14 ("thin delegation here;
  // full character evolution in step 14").
  Future<void> _runPeriodicEvalsInSequence() async {
    // Step 1: Extract user facts
    if (_storageService.memorySettings.autoPersonaEnabled) {
      debugPrint('[Periodic] Step 1/2: Extracting user facts...');
      await _extractFactsInBackground();
    }
    // Step 2: Evolve character
    if (_storageService.memorySettings.characterEvolutionEnabled) {
      debugPrint('[Periodic] Step 2/2: Evolving character...');
      _triggerCharacterEvolution();
    }
  }

  // Fact extraction + consolidate + _isValidFact + static patterns + quality gate moved to
  // fact_extraction.dart (step 13 leaf); thin delegate + late final above; full excision
  // as part of task (deletion part of). See _factExtraction + _extractFactsInBackground thin.
  // Character evolution moved to evolution_service.dart (step 14 leaf); thins + late final
  // above; full excision of block + related as part of task (deletion part of).

  // ── Character Evolution (moved to evolution_service.dart step 14 leaf) ──
  // Full trigger/extract/LLM/prompt/parse/persist/effective layering/group per-char
  // owned in leaf; thins + late final above (after fact); "thin delegation here;
  // full character evolution in step 14". State (flags/maps/counts/status/error)
  // + loadGroupEvolvedFields + session load/save + reset/update (user edit) + public
  // surface coordination stay in god.
  // (Evolution counter unified with fact in _userMessagesSinceLastPeriodicEval)

  bool _isEvolvingCharacter =
      false; // secondary runtime flag (transient guard for evolution_service leaf); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths to prevent leak of in-flight state across contexts (see every "keep reset blocks in sync" + "incomplete zeroing... now complete (see CLAUDE.md)" + evolution_service (stateless or prompt-only; no reset calls needed) + fact_extraction (stateless or prompt-only; no reset calls needed)). The _evolutionStatus / _evolutionError must likewise be zeroed on those paths (prevents stale UI status/error bleed after context switch).
  // Explicit zero sites for evolution flag/status/error (12+ documented; part of "all ~15+" hygiene with briefing lists at 17+ / 31 phrase matches):
  // - startNewChat both branches (fresh + load path)
  // - setActiveCharacter main + empty session
  // - setActiveGroup
  // - _loadLastSession empty + loaded
  // - _loadActiveObjectives empty (0-session)
  // - _loadObjectivesForCurrentSpeaker no-speaker (group)
  // - deleteSession / fork paths
  // - decl init + common reset blocks
  // - _maybeRunPeriodicEvals early guard
  // Cross-refs e.g. setActiveCharacter ~1572 (precedent; lines may shift post edits -- verified live at doc time).
  String _evolutionStatus = '';
  String _evolutionError = '';

  /// Cached evolved fields (loaded from DB on character load)
  final Map<String, String> _evolvedPersonalities = {};
  final Map<String, String> _evolvedScenarios = {};
  int _characterEvolutionCount = 0;
  int get characterEvolutionCount => _characterEvolutionCount;

  /// Public getter: raw evolved personality delta for the active character (null if none).
  /// This bypasses the enabled flag and [Character Growth] layering (returns the stored growth text only).
  /// In group mode, returns null — use getEvolvedPersonalityFor(card) instead.
  /// Injection paths use the _getEffectivePersonality thin (delegates to leaf for full base + layered block when enabled).
  /// Legacy/compat name retained for public surface (see god coord note in step 14 plan).
  String? get getEffectivePersonality {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Public getter: raw evolved scenario delta for the active character (null if none).
  /// This bypasses the enabled flag and [Current Situation] layering.
  /// In group mode, returns null — use getEvolvedScenarioFor(card) instead.
  /// See note on getEffectivePersonality (raw vs layered via thins/leaf).
  String? get getEffectiveScenario {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved personality for a specific character (works in both 1:1 and group mode).
  String? getEvolvedPersonalityFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved scenario for a specific character (works in both 1:1 and group mode).
  String? getEvolvedScenarioFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolution count for a specific character.
  int getEvolutionCountFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    return _groupEvolutionCounts[charId] ?? 0;
  }

  /// Per-character evolution counts (for group mode).
  final Map<String, int> _groupEvolutionCounts = {};

  /// Load evolved fields for all characters in the active group from the
  /// session's JSON map columns (group_evolved_personalities/scenarios).
  Future<void> _loadGroupEvolvedFields() async {
    if (_activeGroup == null || _currentSessionId == null) return;
    try {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session == null) return;
      final personalities = _tryParseJsonMap(session.groupEvolvedPersonalities);
      final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
      for (final ch in _groupCharacters) {
        final charId = _getCharacterIdFromCard(ch);
        _evolvedPersonalities[charId] = personalities[charId] ?? '';
        _evolvedScenarios[charId] = scenarios[charId] ?? '';
        _groupEvolutionCounts[charId] = 0;
      }
    } catch (e) {
      debugPrint('[Evolution] Failed to load group evolved fields: $e');
    }
  }

  /// Whether evolution extraction is currently running.
  bool get isEvolvingCharacter => _isEvolvingCharacter;

  /// Current status message during evolution.
  String get evolutionStatus => _evolutionStatus;

  /// Error message from the last evolution attempt (empty if no error).
  String get evolutionError => _evolutionError;

  // Duplicate old triggerEvolutionNow body excised (thin delegate to leaf is earlier near late final; deletion part of task).

  // Old _triggerCharacterEvolution + _extractCharacterEvolution bodies excised
  // (full logic now in evolution_service leaf step 14; god thins call leaf;
  // target selection / LLM / parse / persist now in leaf via cbs; deletion part of task).
  // (The god thin _triggerCharacterEvolution and triggerEvolutionNow are defined
  // earlier near the late final.)

  /// Reset evolved fields back to original for a character.
  /// In 1:1 mode, targets the active character. In group mode, pass an explicit target.
  Future<void> resetCharacterEvolution({CharacterCard? target}) async {
    final card = target ?? _activeCharacter;
    if (_currentSessionId == null) return;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      // Group mode: remove this char's key from both JSON map columns
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        personalities.remove(charId);
        scenarios.remove(charId);
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      // 1:1 mode: clear plain columns
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: const drift.Value(''),
          evolvedScenario: const drift.Value(''),
          evolutionCount: const drift.Value(0),
        ),
      );
    }

    if (charId != null) {
      _evolvedPersonalities.remove(charId);
      _evolvedScenarios.remove(charId);
      _groupEvolutionCounts.remove(charId);
    }
    if (_activeCharacter != null &&
        (charId == null ||
            _getCharacterIdFromCard(_activeCharacter!) == charId)) {
      _characterEvolutionCount = 0;
    }
    notifyListeners();
    debugPrint(
      '[Evolution] Reset to original for ${card?.name ?? "active character"}',
    );
  }

  /// Update the evolved personality text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedPersonality(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        personalities[charId] = text;
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
          ),
        );
      }
    } else {
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedPersonalities[charId] = text;
    notifyListeners();
  }

  /// Update the evolved scenario text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedScenario(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session != null) {
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        scenarios[charId] = text;
        await _db.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      await _db.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedScenario: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedScenarios[charId] = text;
    notifyListeners();
  }

  /// Get the list of character IDs to search for RAG memory retrieval.
  /// Reads the current character's `memorySources` from the DB and includes
  /// those characters' embedding IDs alongside the current character.
  Future<List<String>> _getMemorySourceIds() async {
    final currentId = _getCharacterId();
    final sourceIds = <String>[currentId]; // always include self

    // Look up cross-character sources from DB
    if (_activeCharacter != null && _activeCharacter!.dbId != null) {
      try {
        final dbChar = await _db.getCharacterById(_activeCharacter!.dbId!);
        final ms = dbChar.memorySources;
        if (ms.isNotEmpty && ms != '[]') {
          final decoded = List<String>.from(
            (jsonDecode(ms) as List).map((e) => e.toString()),
          );
          for (final id in decoded) {
            if (!sourceIds.contains(id)) sourceIds.add(id);
          }
          if (decoded.isNotEmpty) {
            debugPrint('[RAG:Chat] Cross-character sources: $decoded');
          }
        }
      } catch (e) {
        debugPrint('[RAG:Chat] Failed to read memorySources: $e');
      }
    }

    return sourceIds;
  }

  // Thin delegation (full generateSummaryInBackground + prompt macros + history/RAG +
  // 0.3 temp + max=words*3 + central strip think+analysis + update via cbs + save/notify
  // in summary_service step 12; cadence/paused/enabled/flag/scalars/save-load/reset
  // coordination stayed thin in god per plan; "thin delegation here; full summary in step 12").
  Future<void> _generateSummaryInBackground() =>
      _summaryService.generateSummaryInBackground();

  /// Cancel an in-progress Realism evaluation stream (if any).
  ///
  /// Behavior:
  /// - If there is no active realism evaluation and no post-greeting processing,
  ///   this is a no-op.
  /// - Mark cancelling flag, attempt to abort the underlying generation, then
  ///   reset all related UI/state and emit a final notification.
  /// - Do not restart any ongoing flow automatically after cancellation.
  Future<void> cancelRealismEval() async {
    // No-op if there is nothing to cancel
    if (!_isEvaluatingRealism && !_isProcessingGreeting) {
      debugPrint('[Realism] Cancel request ignored — no active realism eval.');
      return;
    }

    _isCancellingRealismEval = true;
    // Signal to any ongoing realism evaluation that a cancel has been requested.
    _realismEvalCancelled = true;
    notifyListeners();

    // Immediately show interruption message in UI
    final senderName = _activeCharacter?.name ?? 'Interruption';
    _messages.add(
      ChatMessage(
        text: 'Realism evaluation interrupted, regenerate response to retry',
        sender: senderName,
        isUser: false,
      ),
    );
    notifyListeners();
    // Save in background - don't await
    Future.microtask(() => _saveChat());

    final llmService =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    debugPrint('[Realism] Realism eval cancel requested');
    try {
      llmService.abortGeneration();
      debugPrint('[Realism] abortGeneration invoked');
    } catch (e) {
      // Ensure we always proceed to reset state even if abortion fails unexpectedly
      debugPrint('[Realism cancel] Unexpected error during abort: $e');
    } finally {
      // Reset all realism-related state
      _realismEvalStreamText = '';
      _pendingRealismMetadata = null;
      _isEvaluatingRealism = false;
      _isProcessingGreeting = false;
      _isCancellingRealismEval = false;
      // NOTE: Do NOT reset _realismEvalCancelled here. It must remain true so that
      // sendMessage() can detect the cancellation and return early. The flag is only
      // reset in sendMessage() after the cancellation is properly handled.
      notifyListeners();
    }
  }

  // ── Prompt Injection Builders (thins only; full in lib/services/chat/prompt_injection/* step 8) ──

  String _getRelationshipInjection() {
    // Thin delegation to builder (full logic + group/1:1 dispatch via cbs in step 8).
    return _relationshipInjection.buildRelationshipInjection();
  }

  /// Phase 2: Invisible inter-character relationship injection.
  /// Returns private guidance for the *current speaker* describing how they
  /// secretly feel about the other members of the group. This is NEVER shown
  /// in the UI (the sidebar bars remain strictly user-focused). It exists only
  /// to let the LLM make the speaker react realistically to their groupmates.
  ///
  /// Example output:
  /// [Private feelings of Alice toward other group members]
  /// - Bob: slightly wary of (-18)
  /// - Charlie: fond of (+42)
  String _getInterCharacterFeelingsInjection() {
    // Thin delegation (full in RelationshipInjection per step 8).
    return _relationshipInjection.buildInterCharacterFeelingsInjection();
  }

  String _getEmotionInjection() {
    // Thin delegation (full in EmotionInjection per step 8; group uses scalar after load).
    return _emotionInjection.buildEmotionInjection();
  }

  String _getBehavioralMechanicsInjection() {
    // Thin delegation (full in BehavioralInjection per step 8).
    return _behavioralInjection.buildBehavioralMechanicsInjection();
  }

  String _getTimeInjection() {
    // Thin delegation (authoritative in TimeInjection per step 8; time_service also thin wrapper).
    return _timeInjection.buildTimeInjection();
  }

  /// Injects a trust-calibrated behavioral frame based on existing trust level (now via RelationshipService).
  /// Tells the model how much of the character's inner self to surface — but
  /// deliberately avoids prescribing specific behaviors, letting the character
  /// persona define what "opening up" actually looks like for THIS character.
  /// Trust tier 0 is now truly neutral — neither trusting nor distrustful.
  String _getTrustBehaviorInjection() {
    // Thin delegation (full in RelationshipInjection per step 8).
    return _relationshipInjection.buildTrustBehaviorInjection();
  }

  /// Returns a prompt fragment that enforces the refractory period, phased by
  /// how far into recovery the character is. The total refractory duration varies
  /// per character (1-8 turns based on personality), so the prompt uses the
  /// ratio of remaining/total to determine the phase.
  String _getNsfwCooldownInjection() {
    // Thin delegation (full in NsfwInjection per step 8).
    return _nsfwInjection.buildNsfwCooldownInjection();
  }

  /// Injects a Chance Time event into the character's response prompt.
  /// Placed AFTER the character name suffix for maximum recency weight.
  /// Consumed after one use (cleared after response generation).
  String _getChanceTimeInjection() {
    // Thin delegation (full in ChaosInjection per step 8; UI flags stayed in god per plan).
    return _chaosInjection.buildChanceTimeInjection();
  }

  // ── LLM Eval Thins (step 9; full in LlmEvalEngine) + Needs Impact Thins (consolidated) + Objective Proposal Thins (step 11) ──
  // 0 new god privates beyond required thin delegates (fire/strip/extract/evaluate* thins + _runPostGenNeedsChecks thin (consolidated to evaluator; the prior separate _check* bodies excised as dead/vestigial per task) + generate/_check thins for objective; void_ count 15; +1 late final); thins only (public surface for now per plan); objective proposal coordination + some
  // prompt/obj mgmt + post-gen needs orchestration (impersonation dance, pre/post group scalars, long-gen, metadata attach) stayed thin in god per plan (qualified in objective_proposal header + here + test + MD).
  // All call sites (5 firing points for realism evals now via realism_evals step 10, gen/check now via objective_proposal step 11, proposal, direct fire/strip/extract in eval paths, post-gen needs) now delegate; non-eval uses ... also route via these thins (centralized, no parallel).

  Future<String?> _fireLLMEval(
    String prompt, {
    void Function(String)? onChunk,
  }) => _llmEvalEngine.fireLLMEval(prompt, onChunk: onChunk);

  String _stripThinkBlocks(String text) =>
      _llmEvalEngine.stripThinkBlocks(text);

  int? _extractJsonInt(String text, String key) =>
      _llmEvalEngine.extractJsonInt(text, key);

  bool? _extractJsonBool(String text, String key) =>
      _llmEvalEngine.extractJsonBool(text, key);

  Future<void> _evaluateRelationshipCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateRelationshipCall(onChunk: onChunk);

  Future<void> _evaluateEmotionalStateCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateEmotionalStateCall(onChunk: onChunk);

  Future<void> _evaluatePhysicalStateCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluatePhysicalStateCall(onChunk: onChunk);

  Future<void> _evaluateNarrativeCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateNarrativeCall(onChunk: onChunk);

  Future<void> _evaluateOneShotCall({void Function(String)? onChunk}) =>
      _realismEvals.evaluateOneShotCall(onChunk: onChunk);

  /// One-shot trust repair evaluator.
  ///
  /// Called automatically on the user's next message after a severe trust drop
  /// (≥ -20 delta). Replaces the normal relationship eval for that turn.
  /// The LLM weighs the explanation against character persona and chat history,
  /// returning a trust_recovery value (0–60). Recovery is capped to prevent
  /// instant restoration from Absolute Distrust.
  Future<void> _evaluateTrustRepairCall(
    String userExplanation, {
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || _activeCharacter == null) return;

    if (_activeCharacter == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final charName = _activeCharacter!.name;
    final persona = _activeCharacter!.personality;
    final recentCount = _messages.length < 10 ? _messages.length : 10;
    final history = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final prompt =
        'You are evaluating whether $charName should partially restore trust '
        'after a severe breach caused by the previous interaction.\n\n'
        'Character Persona: $persona\n\n'
        'Recent chat history (last ~10 messages):\n$history\n\n'
        'The user\'s trust-repair explanation is: "$userExplanation"\n\n'
        'Evaluate ONLY whether this explanation is convincing given:\n'
        '1. The character\'s personality — are they forgiving, stubborn, paranoid, naive?\n'
        '2. The plausibility of the explanation against the chat history\n'
        '3. Whether the explanation contradicts established facts\n\n'
        'Rules:\n'
        '- trust_recovery: 0 (rejected) to 60 (fully convincing)\n'
        '- Paranoid/skeptical characters: give 0–20 even for good explanations\n'
        '- Forgiving/naive characters: may give 30–60 for plausible explanations\n'
        '- Do NOT give 60 unless the explanation perfectly resolves the breach\n'
        '- "reason" must be 1 short sentence from the character\'s POV\n\n'
        'Respond with ONLY: {"trust_recovery": <0-60>, "verdict": "accepted|partial|rejected", "reason": "<brief>"}\n';

    try {
      debugPrint('[Realism:TrustRepair] Evaluating repair attempt...');
      final raw = await _fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;

      final text = _stripThinkBlocks(raw).trim();

      final verdictMatch = RegExp(
        r'"verdict"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(text);

      final recovery = (_extractJsonInt(text, 'trust_recovery') ?? 0).clamp(
        0,
        60,
      );
      final verdict = verdictMatch?.group(1) ?? 'rejected';
      final reason = reasonMatch?.group(1) ?? '';

      if (recovery > 0) {
        _relationshipService.applyTrustDelta(recovery);
        debugPrint(
          '[Realism:TrustRepair] $verdict — recovered $recovery → ${_relationshipService.trustLevel} ($reason)',
        );
      } else {
        debugPrint('[Realism:TrustRepair] Rejected — no recovery ($reason)');
      }

      // Surface verdict in message metadata so swipe history can record it
      _pendingRealismMetadata = {
        ...?_pendingRealismMetadata,
        'trust_repair_verdict': verdict,
        'trust_repair_recovery': recovery,
        if (reason.isNotEmpty) 'trust_repair_reason': reason,
      };

      _saveChat();
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:TrustRepair] Failed: $e');
    }
  }

  Map<String, dynamic> _captureRealismState({Map<String, int>? preTurn}) {
    final state = {
      'affectionScore': _relationshipService.affectionScore,
      'relationshipTier': _relationshipService.relationshipTier,
      'longTermScore': _relationshipService.longTermScore,
      'longTermTier': _relationshipService.longTermTier,
      'turnsSinceLongTermCheck': _relationshipService.turnsSinceLongTermCheck,
      'shortTermDeltasSummary': _relationshipService.shortTermDeltasSummary,
      'moodDecayCounter': _moodDecayCounter,
      'characterEmotion': _characterEmotion,
      'emotionIntensity': _emotionIntensity,
      'timeOfDay': _timeService.timeOfDay,
      'dayCount': _timeService.dayCount,
      'startDayOfWeek': _timeService.startDayOfWeekAnchor,
      'arousalLevel': _nsfwService.arousalLevel,
      'cooldownTurnsRemaining': _nsfwService.cooldownTurnsRemaining,
      'cooldownTurnsTotal': _nsfwService.cooldownTurnsTotal,
      'trustLevel': _relationshipService.trustLevel,
      'activeFixation': _relationshipService.activeFixation,
      'fixationLifespan': _relationshipService.fixationLifespan,
      'spatialStance': _relationshipService.spatialStance,
    };

    // Include needs snapshot when the simulation is active (clean port).
    // Note: 'enabled' is deliberately omitted from the per-message snapshot.
    // The enabled flag is authoritative from the character card / current session
    // (see setNeedsSimEnabled and ext seeding). Snapshots only carry the vector
    // for timeline continuity while the sim is on. This prevents historical
    // snapshots from resurrecting a stale enabled state after a mid-chat toggle-off.
    if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
      // Explicit <String, dynamic> for the needs snapshot so that 'deltas' (Map with
      // mixed int/String values from computeNeedsDeltasWithReasons) can be attached
      // without runtime generic value-type violation (the 'vector' entry statically
      // infers Map<String,int>, which would lock the literal's value type and reject
      // the deltas map on []=).
      final needsSnap = <String, dynamic>{
        'vector': Map<String, int>.from(_needsSimulation.vector),
      };
      state['needs'] = needsSnap;

      final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
        preTurn ?? const <String, int>{},
      );
      if (needsDeltas.isNotEmpty) {
        needsSnap['deltas'] = needsDeltas;
      }
    }

    return state;
  }

  // ── Phase 1: Per-character realism evaluation for the upcoming speaker ────
  /// Runs targeted realism evaluation for the specific character who is about
  /// to speak next in a group chat. This is the core of making realism work
  /// on a per-character, turn-timed basis.
  ///
  /// Uses temporary impersonation of _activeCharacter so that all existing
  /// realism eval methods (_evaluateOneShotCall, _evaluateRelationshipCall, etc.)
  /// and their parsing/inertia logic are reused without duplication.
  Future<void> _evaluateRealismForUpcomingGroupSpeaker(
    CharacterCard speaker,
  ) async {
    if (!isGroupRealismActive || observerMode) return;

    final charId = _getCharacterIdFromCard(speaker);
    if (charId.isEmpty) return;

    debugPrint(
      '[Realism:Group] Running pre-turn eval for upcoming speaker: ${speaker.name} ($charId)',
    );

    // Save previous 1:1 context (normally null in pure group sessions)
    final previousActiveCharacter = _activeCharacter;

    // Impersonate this speaker for the duration of the eval so all existing
    // LLM eval methods, guards, name/personality reads, and delta application
    // logic work exactly as they do for 1:1 chats.
    _activeCharacter = speaker;

    // Load this speaker's persisted group realism state into the scalar fields
    // that the eval methods will read and mutate.
    _loadGroupRealismIntoScalars(charId);

    // Phase 2: Ensure hidden inter-character relationship tracking is seeded
    // for all other group members (neutral 0). This happens on the speaker's
    // first turn with realism so the invisible feelings map is always present.
    _relationshipService.ensureInterCharacterRelationshipsSeeded(charId);

    _isEvaluatingRealism = true;
    _realismEvalStreamText = '';
    notifyListeners();

    // Capture this speaker's pre-turn needs vector (before decay + eval)
    Map<String, int>? preTurnVector;
    if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
      preTurnVector = Map<String, int>.from(_needsSimulation.vector);
    }

    // Temporarily load this speaker's personal objectives so the narrative
    // evaluation (and one-shot) sees the correct primary/secondary context
    // for "proposed_objective" generation. This is required for 1:1 parity.
    final previousObjectives = List<Objective>.from(_activeObjectives);
    final speakerObjectives = await getActiveObjectivesFor(speaker);
    _activeObjectives = speakerObjectives.where((o) => o.active).toList();

    void handleChunk(String chunk) {
      _realismEvalStreamText += chunk;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
        try {
          notifyListeners();
        } catch (_) {}
      });
    }

    try {
      // Respect early cancellation
      if (_realismEvalCancelled) {
        debugPrint(
          '[Realism:Group] Evaluation cancelled before LLM calls for ${speaker.name}',
        );
        _realismEvalCancelled = false;
        return;
      }

      if (_storageService.realismSettings.realismOneShotEval) {
        await _evaluateOneShotCall(onChunk: handleChunk);
      } else {
        await Future.wait([
          _evaluateRelationshipCall(onChunk: handleChunk),
          _evaluateEmotionalStateCall(onChunk: handleChunk),
          _evaluatePhysicalStateCall(onChunk: handleChunk),
          _evaluateNarrativeCall(onChunk: handleChunk),
        ]);
      }

      // Handle cancellation after the eval calls
      if (_realismEvalCancelled) {
        debugPrint(
          '[Realism:Group] Evaluation cancelled during/after LLM calls for ${speaker.name}',
        );
        _realismEvalCancelled = false;
        return;
      }

      // Harvest the now-updated scalar fields back into this speaker's
      // _groupRealism entry so prompt injection and UI see fresh values.
      _saveScalarsIntoGroupRealism(charId);

      // Synthesize metadata for timeline / chips (best-effort, same as 1:1 path)
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
      _pendingRealismMetadata!['realism_state'] = _captureRealismState(
        preTurn: preTurnVector,
      );

      if (_needsSimEnabled) {
        final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(
          preTurnVector ?? const <String, int>{},
        );
        if (needsDeltas.isNotEmpty) {
          _pendingRealismMetadata!['needs_deltas'] = needsDeltas;
        }
      }

      _saveChat();
    } finally {
      // Always restore previous context and clear busy state
      _activeCharacter = previousActiveCharacter;
      _activeObjectives = previousObjectives;
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      _isEvaluatingRealism = false;
      notifyListeners();
    }
  }

  /// Loads the given group character's realism values from _groupRealism into
  /// the single-character scalar fields so the existing eval methods can
  /// operate on them during impersonation.
  void _loadGroupRealismIntoScalars(String charId) {
    // Relationship (affection/trust/fix/tiers etc) now via service load helper (uses the same _getGroup* internally via cbs).
    _relationshipService.loadRelationshipScalarsForSpeaker(charId);
    // Nsfw (arousal + cooldown + nsfwEnabled per char) via service (extends prior arousal-only for full group parity).
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    _nsfwService.loadNsfwScalarsForSpeaker(charId);

    _characterEmotion = _getGroupString(charId, 'emotion');
    _emotionIntensity = _getGroupString(
      charId,
      'emotionIntensity',
      defaultValue: 'moderate',
    );

    // Needs vector (if any persisted for this char)
    final needs = _getGroupNeeds(charId);
    if (needs.isNotEmpty) {
      _needsSimulation.restoreFromSnapshot({'vector': needs});
    } else if (_needsSimEnabled) {
      // Fresh start for a group member who has never had needs for this group chat.
      // Use full 100 to match 1:1 "new chat" behavior (prevents bleed perception).
      _needsSimulation.initializeFresh();
    }
  }

  /// Writes the current scalar realism fields back into the target group
  /// character's _groupRealism entry after an impersonated eval round.
  void _saveScalarsIntoGroupRealism(String charId) {
    // Relationship scalars (affection/long/trust/fix/tiers/spatial) now via service.
    _relationshipService.saveRelationshipScalarsToGroup(charId);
    // Nsfw scalars (arousal + cooldown + enabled) now via service (for group per-char persistence parity).
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    _nsfwService.saveNsfwScalarsToGroup(charId);

    if (_characterEmotion.isNotEmpty) {
      _setGroupRealismValue(charId, 'emotion', _characterEmotion);
    }
    if (_emotionIntensity.isNotEmpty) {
      _setGroupRealismValue(charId, 'emotionIntensity', _emotionIntensity);
    }

    // Persist current needs vector for this speaker
    if (_needsSimulation.vector.isNotEmpty) {
      _setGroupNeeds(charId, Map<String, int>.from(_needsSimulation.vector));
    }
  }

  /// Public API: Focus the personal objectives of a specific group member so the
  /// existing objective management UI and generation can operate on them.
  /// Does nothing in 1:1 mode.
  Future<void> focusObjectivesForGroupCharacter(CharacterCard character) async {
    if (_activeGroup == null) return;
    final charId = _getCharacterIdFromCard(character);
    final objs = await _db.getObjectivesForCharacter(
      charId,
      chatId: _currentSessionId,
    );
    _activeObjectives = objs.where((o) => o.active).toList();
    notifyListeners();
  }

  /// Loads the active objectives for the given character in the current session.
  /// Safe to call from group objective UIs — does not mutate global _activeObjectives.
  Future<List<Objective>> getActiveObjectivesFor(
    CharacterCard character,
  ) async {
    if (_currentSessionId == null) return const [];
    final charId = _getCharacterIdFromCard(character);
    try {
      return await _db.getActiveObjectives(charId, chatId: _currentSessionId!);
    } catch (e) {
      debugPrint('[Objective] Failed to load for ${character.name}: $e');
      return const [];
    }
  }

  // ── Group Creation Baseline Seeding (bond/trust/emotion/time/day only) ──

  /// Returns the immutable creation-time baseline realism values for a group member.
  /// Only the allowed seeding fields are exposed: affection (bond), trust, emotion, timeOfDay, dayCount.
  Map<String, dynamic> getBaselineSeedForGroupCharacter(
    CharacterCard character,
  ) {
    if (_activeGroup == null) return {};
    final charId = _getCharacterIdFromCard(character);
    try {
      final json = jsonDecode(_activeGroup!.baselineRealismState);
      if (json is Map && json.containsKey(charId)) {
        final data = json[charId] as Map<String, dynamic>? ?? {};
        return {
          'affection': (data['affection'] as num?)?.toInt() ?? 50,
          'trust': (data['trust'] as num?)?.toInt() ?? 50,
          'emotion': (data['emotion'] as String?) ?? 'neutral',
          'emotionIntensity':
              (data['emotionIntensity'] as String?) ?? 'moderate',
          'timeOfDay': (data['timeOfDay'] as String?) ?? 'morning',
          'dayCount': (data['dayCount'] as num?)?.toInt() ?? 1,
        };
      }
    } catch (_) {}
    return {
      'affection': 50,
      'trust': 50,
      'emotion': 'neutral',
      'emotionIntensity': 'moderate',
      'timeOfDay': 'morning',
      'dayCount': 1,
    };
  }

  /// Updates the immutable creation baseline for a group member.
  /// Only allowed fields are accepted. This should only be called during group creation seeding.
  void setBaselineSeedForGroupCharacter(
    CharacterCard character,
    Map<String, dynamic> values,
  ) {
    if (_activeGroup == null) return;
    final charId = _getCharacterIdFromCard(character);

    Map<String, dynamic> baseline;
    try {
      baseline = Map<String, dynamic>.from(
        jsonDecode(_activeGroup!.baselineRealismState),
      );
    } catch (_) {
      baseline = {};
    }

    baseline[charId] = {
      'affection': (values['affection'] as num?)?.toInt() ?? 50,
      'trust': (values['trust'] as num?)?.toInt() ?? 50,
      'emotion': (values['emotion'] as String?) ?? 'neutral',
      'emotionIntensity': (values['emotionIntensity'] as String?) ?? 'moderate',
      'timeOfDay': (values['timeOfDay'] as String?) ?? 'morning',
      'dayCount': (values['dayCount'] as num?)?.toInt() ?? 1,
    };

    _activeGroup!.baselineRealismState = jsonEncode(baseline);
    notifyListeners();
  }

  /// Loads the personal objectives for the current/next speaker into _activeObjectives
  /// when in group mode. This makes the existing objective UI, generation, and injection
  /// work per-character in groups without duplicating the entire objective system.
  Future<void> _loadObjectivesForCurrentSpeaker() async {
    if (_activeGroup == null || _currentSessionId == null) return;

    final speaker = nextCharacter ?? _groupCharacters.firstOrNull;
    if (speaker == null) {
      _activeObjectives = [];
      _messagesSinceLastCheck = 0;
      _isCheckingCompletion = false;
      _summaryPaused =
          false; // explicit secondary zero for _summaryPaused (symmetric; _loadObjectivesForCurrentSpeaker no-speaker hygiene)
      _isSummaryGenerating =
          false; // secondary zero in _loadObjectivesForCurrentSpeaker no-speaker (group hygiene for summary flag)
      _userMessagesSinceLastPeriodicEval = 0;
      _isExtractingFacts =
          false; // secondary fact flag + counter zero in _loadObjectivesForCurrentSpeaker no-speaker (group hygiene; fact_extraction)
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      _evolutionError =
          ''; // explicit evo flag/status/error zero in _loadObjectivesForCurrentSpeaker no-speaker (group hygiene; evolution_service (stateless or prompt-only; no reset calls needed))
      notifyListeners();
      return;
    }

    final charId = _getCharacterIdFromCard(speaker);
    final objs = await _db.getObjectivesForCharacter(
      charId,
      chatId: _currentSessionId,
    );

    _activeObjectives = objs.where((o) => o.active).toList();
    notifyListeners();
  }

  /// One-time seeding of objectives that were carried in an imported Group Card.
  /// Called after group state is loaded for a freshly imported group.
  Future<void> _seedImportedMemberObjectivesIfPresent() async {
    if (_activeGroup == null || _currentSessionId == null) return;

    try {
      final stateJson = _activeGroup!.defaultMemberRealismState;
      if (stateJson.isEmpty || stateJson == '{}') return;

      final map = jsonDecode(stateJson);
      if (map is! Map) return;

      final importedObj = map['imported_member_objectives'];
      if (importedObj is! Map) return;

      for (final entry in importedObj.entries) {
        final charId = entry.key.toString();
        final list = entry.value as List? ?? [];
        for (final objData in list) {
          final objMap = objData as Map<String, dynamic>? ?? {};
          final newId =
              'obj_${DateTime.now().millisecondsSinceEpoch}_${charId.hashCode}';
          await _db.insertObjective(
            ObjectivesCompanion.insert(
              id: newId,
              characterId: charId,
              chatId: drift.Value(_currentSessionId!),
              objective:
                  objMap['objective']?.toString() ?? 'Imported objective',
              tasks: drift.Value(objMap['tasks']?.toString() ?? '[]'),
              active: const drift.Value(true),
              isPrimary: drift.Value(objMap['isPrimary'] == true),
              checkFrequency: drift.Value(
                (objMap['checkFrequency'] as num?)?.toInt() ?? 3,
              ),
              injectionDepth: drift.Value(
                (objMap['injectionDepth'] as num?)?.toInt() ?? 4,
              ),
            ),
          );
        }
      }

      // Remove the marker so it doesn't seed again
      map.remove('imported_member_objectives');
      _activeGroup!.defaultMemberRealismState = jsonEncode(map);
      await _saveChat();
    } catch (_) {}
  }

  String _getNeedsInjection() {
    // Thin delegation (full in NeedsInjection per step 8; group per-char via cb, suppression etc).
    return _needsInjection.buildNeedsInjection();
  }

  void _restoreRealismStateFromMessage(ChatMessage? msg) {
    if (msg == null) return;

    // Check if the current visible node has an active swipe metadata array or just the base metadata
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) {
      debugPrint(
        '[Realism] No time-travel snapshot found in message. Legacy state kept.',
      );
      return;
    }

    final state = meta['realism_state'] as Map<String, dynamic>;
    _relationshipService.restoreFromMessageState(state);
    _moodDecayCounter = state['moodDecayCounter'] as int? ?? _moodDecayCounter;
    _characterEmotion =
        state['characterEmotion'] as String? ?? _characterEmotion;
    _emotionIntensity =
        state['emotionIntensity'] as String? ?? _emotionIntensity;

    _timeService.restoreTimeFromRealismState(state);

    _nsfwService.restoreNsfwFromRealismState(state);

    // v3.0 Restorations (relationship via service; already covered by restoreFromMessageState above for most).
    // (Direct sets removed; service owns the scalars.)

    // Needs simulation snapshot (clean port)
    // Only restore the vector if the sim is currently enabled for this session.
    // Never let a historical snapshot flip _needsSimEnabled back on (supports
    // clean mid-chat toggle-off via setNeedsSimEnabled without stale state).
    if (state.containsKey('needs') &&
        state['needs'] is Map &&
        _needsSimEnabled) {
      final needsData = state['needs'] as Map;
      _needsSimulation.restoreFromSnapshot(needsData);
    }

    debugPrint(
      '[Realism] Engine state successfully rolled back to match timeline.',
    );
  }

  /// Runs all post-generation needs-related checks (climax, sexual activity,
  /// daily activities, fulfillment) via thin delegate to the consolidated
  /// NeedsImpactEvaluator (simple model + optional Director authority review loop).
  /// Orchestration (guards, group impersonation dance + loadGroupRealismIntoScalars
  /// before call so prompts see correct $charName/personality/stance, preTurn
  /// snapshot for chips, post _saveScalarsIntoGroupRealism + attach needs_deltas,
  /// (orchestration + impersonation dance in god; full in evaluator).
  Future<void> _runPostGenNeedsChecks(String responseText) async {
    await _needsImpactEvaluator.evaluateAndApply(responseText);
  }

  // (unified thin + evaluator; prior _check* excised as dead. See CLAUDE.md).

  // ── Score / State Helpers (thinned; core logic + counters in RelationshipService) ──

  /// Apply short-term relationship decay (2 points per 10 turns toward 0)
  /// This prevents relationships from being permanently stuck at extremes.
  void _applyMoodDecay() {
    // Decay mechanism moved to RelationshipService (applyShortTermDecay).
    // Counter, 1:1/group branches, inter-char decay all delegated for mechanical fidelity.
    _relationshipService.applyShortTermDecay();
  }

  // ── Public Toggle Methods ──

  Future<void> setRealismEnabled(bool enabled) async {
    _realismEnabled = enabled;
    // Anchor the narrative weekday to the real-world day when realism first turns on for this session.
    // Only set if not already anchored (0 = legacy/unset). This prevents re-anchoring on toggle-off/on
    // for long-running sessions, keeping Day N stable across restarts.
    if (enabled) {
      _timeService.ensureStartDayOfWeekAnchored();
    }

    if (enabled && _activeGroup == null && _activeCharacter != null) {
      // ── Solution 1: Pending greeting flag ────────────────────────────
      // The greeting was placed while realism was off. Fire the baseline
      // eval now that the user has explicitly enabled it.
      if (_greetingEvalPending && !_hasRealismBaseline) {
        debugPrint(
          '[Realism] Consuming pending greeting eval (user enabled realism after load).',
        );
        _runPostGreetingEval();
      }
      // ── Solution 3: Retroactive scan on enable ────────────────────────
      // Realism was enabled mid-conversation with no baseline captured yet
      // (emotion is blank, affection is zero, multiple messages exist).
      // Run a full retrospective eval against all visible messages.
      else if (!_hasRealismBaseline && _messages.length > 1) {
        debugPrint(
          '[Realism] No baseline detected — running retroactive scan on enable.',
        );
        _runRetroactiveBaselineEval();
      }
    }

    if (!enabled) {
      // IMPORTANT: Do NOT zero out realism state when disabling!
      // Just stop using it. State persists in memory/DB so re-enabling restores it.
      // Old behavior was destructive - it deleted all character building progress.
      debugPrint(
        '[Realism] Disabled (preserving state: bond=${_relationshipService.affectionScore}, trust=${_relationshipService.trustLevel}, emotion=$_characterEmotion)',
      );
    }
    await _saveChat();
    notifyListeners();
  }

  Future<void> setNsfwCooldownEnabled(bool enabled) async {
    _nsfwService.setNsfwCooldownEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  Future<void> setPassageOfTimeEnabled(bool enabled) async {
    _timeService.setPassageOfTimeEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  /// Toggles the Needs Simulation for the current session.
  ///
  /// - `true`: initializes the default need vector (if empty) then begins tracking.
  /// - `false`: clears the in-memory vector (levels are discarded for this session).
  ///
  /// The change is persisted with the session and broadcast via [notifyListeners].
  /// Matches the side-effect style of [setNsfwCooldownEnabled] and [setChaosModeEnabled].
  Future<void> setNeedsSimEnabled(bool enabled) async {
    _needsSimEnabled = enabled;
    _needsSimEnabled =
        enabled; // setEnabled removed; control in god _needsSimEnabled (sim reads via cb)
    await _saveChat();
    notifyListeners();
  }

  // ── Manual Time Nudge ────────────────────────────────────────────────────

  /// Called by the sidebar chevron buttons. delta = +1 (forward) or -1 (back).
  /// Thin delegation to TimeService (core logic + cb-driven patch). Save/notify
  /// + realism guard kept in god wrapper (UI coordination).
  Future<void> nudgeTimePeriod(int delta) async {
    if (!_realismEnabled) return;
    _timeService.nudgeTimePeriod(delta);
    await _saveChat();
    notifyListeners();
  }

  // ── Chaos Mode / Chance Time (thin delegation to extracted service) ──────
  // Control sets delegate fully (like needsSimEnabled precedent). Actions thin to
  // handle the UI-coordination flags (pendingEvent, completer) that stay in god.
  // All impl (pressure math, pools, roll, apply core, etc.) deleted from here.

  Future<void> setChaosModeEnabled(bool enabled) async {
    _chaosModeService.setModeEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  Future<void> setChaosNsfwEnabled(bool enabled) async {
    _chaosModeService.setNsfwEnabled(enabled);
    await _saveChat();
    notifyListeners();
  }

  /// Clear the pending event after the UI has consumed it.
  void clearChanceTimeEvent() {
    _pendingChanceTimeEvent = null;
    // no notifyListeners — avoids rebuild storms; UI already consumed it
  }

  /// Returns 8 randomly-sampled events for the wheel UI to display.
  List<String> spinWheelEvents() {
    return _chaosModeService.spinWheelEvents();
  }

  /// Called by the wheel overlay once the animation lands on an event.
  /// Thin wrapper: compute display ({{char}} replace), set UI flag, delegate core
  /// (pressure/injection/metadata/save/notify) to service, then complete completer.
  Future<void> applyChanceTimeResult(String event, String charName) async {
    final display = event.replaceAll('{{char}}', charName);
    _pendingChanceTimeEvent = display;
    await _chaosModeService.applyPreparedEvent(display);
    // Resume the paused sendMessage flow (UI coordination stays in god)
    _chanceTimeCompleter?.complete();
  }

  /// Per-turn auto-trigger check. Delegates to service (verbatim roll/pressure logic).
  bool checkAndTickChaosPressure() {
    return _chaosModeService.checkAndTickChaosPressure();
  }

  // (Chance Time pools moved verbatim to ChaosModeService; deletion complete.)

  // ── Central dispose guard (rec 2 from PR #47) ─────────────────────────────────
  // Overrides protect every notifyListeners() call (many direct + after async DB/repo
  // work) from post-dispose use. Placed here (not a new void _ private) to obey god
  // rules (void _ count must stay exactly 15 live grep after every edit + final).
  // Deletion of the now-redundant per-site try/catch guard in _loadActiveObjectives
  // (and its comment) is part of this task (see that site for the removed code).
  /// Update a global group decay rate, propagating it to all group members' PNGs
  Future<void> setGroupNeedsDecayRate(String key, int value) async {
    if (_activeGroup == null) return;
    _groupDecayRates[key] = value;

    if (_characterRepository != null) {
      final v2Service = V2CardService();
      final db = await AppDatabase.instance();
      
      for (final char in _groupCharacters) {
        final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
        final newExt = ext.copyWith(
          needsDecayHunger: key == 'hunger' ? value : null,
          needsDecayBladder: key == 'bladder' ? value : null,
          needsDecayEnergy: key == 'energy' ? value : null,
          needsDecaySocial: key == 'social' ? value : null,
          needsDecayFun: key == 'fun' ? value : null,
          needsDecayHygiene: key == 'hygiene' ? value : null,
          needsDecayComfort: key == 'comfort' ? value : null,
        );
        char.frontPorchExtensions = newExt;

        if (char.imagePath != null) {
          final file = File(char.imagePath!);
          if (await file.exists()) {
            await v2Service.saveCardAsPng(char, char.imagePath!, char.imagePath!);
          }
        }

        if (char.dbId != null) {
          await db.updateGroupMember(
            GroupMembersCompanion(
              id: drift.Value(char.dbId!),
              frontPorchExtensions: drift.Value(jsonEncode(newExt.toJson())),
            ),
          );
        }
      }
    }

    await _saveChat();
    notifyListeners();
  }

  /// Update a decay rate for the active 1:1 character
  Future<void> setNeedsDecayRate(String key, int value) async {
    if (_activeCharacter == null || _characterRepository == null) return;

    final ext = _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();
    final newExt = ext.copyWith(
      needsDecayHunger: key == 'hunger' ? value : null,
      needsDecayBladder: key == 'bladder' ? value : null,
      needsDecayEnergy: key == 'energy' ? value : null,
      needsDecaySocial: key == 'social' ? value : null,
      needsDecayFun: key == 'fun' ? value : null,
      needsDecayHygiene: key == 'hygiene' ? value : null,
      needsDecayComfort: key == 'comfort' ? value : null,
    );
    _activeCharacter!.frontPorchExtensions = newExt;

    await _characterRepository!.updateCharacter(_activeCharacter!);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
