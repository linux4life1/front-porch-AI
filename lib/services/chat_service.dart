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
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/chat_participant.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/group_member.dart';
import 'package:front_porch_ai/services/chat/member_origin_resolver.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/services/expression_classifier.dart'; // top-level for ExpressionClassifierService type in @Dep shim (pre-existing)
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/services/chat/cast_detector.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';
import 'package:front_porch_ai/services/chat/scene_guest_factory.dart';
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
import 'package:front_porch_ai/services/chat/prompt_injection/realism_state_injection.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/chat/objective_proposal.dart';
import 'package:front_porch_ai/services/chat/summary_service.dart';
import 'package:front_porch_ai/services/chat/fact_extraction.dart';
import 'package:front_porch_ai/services/chat/evolution_service.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:drift/drift.dart' as drift;

// Cohesive method groups extracted into part files to keep this file shrinking
// toward the 500-line cap (see CLAUDE.md). Parts share this library's imports and
// private members; behaviour is unchanged.
part 'chat/chat_service_group_read.dart';
part 'chat/chat_service_group_settings.dart';
part 'chat/chat_service_evolution.dart';
part 'chat/chat_service_sillytavern.dart';
part 'chat/chat_service_group_realism_helpers.dart';
part 'chat/chat_service_history.dart';
part 'chat/chat_service_group_membership.dart';
part 'chat/chat_service_reprocess.dart';
part 'chat/chat_service_chat_entry.dart';
part 'chat/chat_service_group_entry.dart';
part 'chat/chat_service_session_state.dart';
part 'chat/chat_service_session_load.dart';
part 'chat/chat_service_realism_evals.dart';
part 'chat/chat_service_actions.dart';
part 'chat/chat_service_objectives.dart';
part 'chat/chat_service_realism_dance.dart';
part 'chat/chat_service_speaker_objectives.dart';
part 'chat/chat_service_impersonate.dart';
part 'chat/chat_service_session_manage.dart';
part 'chat/chat_service_generation.dart';
part 'chat/chat_service_cast.dart';

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
  ImageGenService? _imageGenService;
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

  /// Whether a completion check is currently running.
  ///
  /// Kept in the class body (not the objectives extension) because
  /// [FakeChatService] overrides it in golden tests — extension members are
  /// statically dispatched and cannot be overridden.
  bool get isCheckingCompletion => _isCheckingCompletion;

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

  // ── Scene Guests (Lite NPCs) ──────────────────────────────────────────────
  // Persistent guest characters added to a 1:1 scene. They are real library
  // characters that speak in their own bubble via the existing generation
  // engine but carry NO Realism Engine / Needs state (parity-safe). Stored as
  // dbIds inside the session's groupRealismState column (always '{}' for plain
  // 1:1 sessions) so no schema change is needed. Group sessions never use these.
  final List<String> _sceneGuestIds = [];
  final List<CharacterCard> _sceneGuestCards = [];

  // Phase 3 — per-guest Character Evolution (trait development). Keyed by the
  // guest's stable charId (same key the EvolutionService uses). The evolved
  // *text* lives in the shared `_evolvedPersonalities` / `_evolvedScenarios`
  // maps (so the existing effective-personality layering applies on guest turns
  // for free); only the per-guest evolution *count* is tracked separately so a
  // guest evolves on its own participation cadence and we never perturb the
  // active character's evolution count/state. Persisted alongside the guest ids
  // in the 1:1 `groupRealismState` blob (no schema change). Carries ZERO
  // Realism/Needs work — it is a sibling of the existing evolution trigger.
  final Map<String, int> _guestEvolutionCounts = {};

  /// A one-shot departure instruction consumed by the NEXT primary 1:1
  /// generation so the active character narrates the guest leaving. Set by
  /// `/exit`, cleared after a single injection.
  String? _pendingGuestDeparture;

  /// A pending request to open the Scene Guest picker (the `/join` flow). Holds
  /// the initial search filter ('' = show everyone); null = no picker pending.
  /// Surfaced to the chat UI exactly like [pendingGuestDetection] — set + clear
  /// here with [notifyListeners]; the page observes it and shows the picker once.
  String? _pendingGuestPickerFilter;

  /// Transient one-line status for the Scene Guest create/join flow, shown as an
  /// inline banner above the input and NEVER saved to chat history (replaces the
  /// old per-step 'System' chat messages that both littered the scene and were
  /// persisted into it). Updated in place across the steps, then auto-clears.
  String? _guestActivityStatus;
  bool _guestActivityIsError = false;
  Timer? _guestStatusClearTimer;

  /// True while a guest is being created/entered. The mint runs a separate LLM
  /// call that does NOT set `_isGenerating`, so this is the guard that blocks a
  /// user message (or regen/swipe) from racing the in-flight guest creation.
  bool _guestBusy = false;

  /// Set when a guest's background portrait was just written to its card PNG, so
  /// the UI can evict that path from the image cache and show the new art (image
  /// cache lives in the widget layer; this service is foundation-only).
  String? _guestAvatarEvictPath;

  /// The persistent Scene Guests currently in this 1:1 scene (resolved cards).
  List<CharacterCard> get sceneGuestCards =>
      List.unmodifiable(_sceneGuestCards);

  /// Initial filter for a pending `/join` picker, or null when none is pending.
  String? get pendingGuestPickerFilter => _pendingGuestPickerFilter;

  bool _pendingGuestPickerFull = false;

  /// Whether the pending picker should add the picked character as a FULL member
  /// (group member / 1:1->group convert) vs a lite Scene Guest.
  bool get pendingGuestPickerFull => _pendingGuestPickerFull;

  /// Transient Scene Guest create/join status line (null when idle).
  String? get guestActivityStatus => _guestActivityStatus;

  /// Whether [guestActivityStatus] is an error (drives the banner styling).
  bool get guestActivityIsError => _guestActivityIsError;

  /// True while a Scene Guest is being created/entered (input is disabled).
  bool get isGuestBusy => _guestBusy;

  /// A guest card image path whose cache the UI should evict (then call
  /// [consumeGuestAvatarEvict]); null when there is nothing to refresh.
  String? get guestAvatarEvictPath => _guestAvatarEvictPath;

  /// Clear the pending avatar-evict signal after the UI has evicted the path.
  void consumeGuestAvatarEvict() => _guestAvatarEvictPath = null;

  // ── /exit undo ──────────────────────────────────────────────────────────
  // After `/exit`, a brief UNDO is offered: delete the generated departure
  // message (reverting its host realism via deleteMessage's time-travel
  // rollback) and re-add the guest. Their evolution counts + RAG memory are NOT
  // cleared by exit, so re-adding the id restores full context. The offer is
  // consumed by the UI (one SnackBar) but the undo data stays valid until the
  // user sends a real message / switches chats.
  CharacterCard? _exitUndoGuest;
  ChatMessage? _exitUndoMessage;
  String? _exitUndoOfferName;

  /// Set when a FULL group member's `/exit` is awaiting commit. They have said
  /// goodbye and left the live roster, but their DB row/realism/evolution/quests/
  /// memory are untouched and the real removal (plus any collapse to a 1:1) is
  /// deferred until the user continues — so [undoLastExit] can restore them
  /// losslessly. Committed in `sendMessage` via [_commitPendingMemberExit].
  CharacterCard? _pendingMemberExit;

  /// Name to show in the UNDO SnackBar (null = nothing to offer).
  String? get exitUndoOfferName => _exitUndoOfferName;

  /// Consume the one-shot UNDO offer (the SnackBar was shown); the undo itself
  /// stays available via [undoLastExit] until invalidated.
  void consumeExitUndoOffer() => _exitUndoOfferName = null;

  /// Capture undo state right after a `/exit` departure turn finished. The
  /// just-generated host message (if any) is the departure to delete on undo.
  void armSceneGuestExitUndo(CharacterCard guest) {
    final departure =
        (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.sender != 'System')
        ? _messages.last
        : null;
    _exitUndoGuest = guest;
    _exitUndoMessage = departure;
    _exitUndoOfferName = guest.name;
    notifyListeners();
  }

  void _clearExitUndo() {
    _exitUndoGuest = null;
    _exitUndoMessage = null;
    _exitUndoOfferName = null;
    // A pending full-member exit that is cleared WITHOUT committing (context
    // switch / new chat) is simply cancelled: the member's row was never deleted,
    // so they stay. The sendMessage commit path runs _commitPendingMemberExit
    // before this, so a real "continue" still finalizes the removal.
    _pendingMemberExit = null;
  }

  /// Undo the last `/exit`: delete the departure message (which reverts the host
  /// realism it applied, via [deleteMessage]'s rollback) and restore the guest
  /// to the scene with their full context (evolution + memory were never wiped).
  Future<void> undoLastExit() async {
    // Full group member (deferred-deletion): the member's DB row, realism,
    // evolution, quests and memory were never touched — restoring is just a
    // roster reload plus deleting their goodbye turn (which reverts the realism
    // that turn applied). The destructive removal never ran, so there is nothing
    // to un-collapse.
    final pendingMember = _pendingMemberExit;
    if (pendingMember != null) {
      final departure = _exitUndoMessage;
      _pendingMemberExit = null;
      _clearExitUndo();
      if (departure != null) {
        final idx = _messages.indexOf(departure);
        if (idx >= 0) deleteMessage(idx); // removes + reverts realism + saves
      }
      await _reloadGroupRoster();
      _setGuestStatus('${pendingMember.name} is back in the chat.');
      notifyListeners();
      return;
    }

    final guest = _exitUndoGuest;
    final departure = _exitUndoMessage;
    if (guest == null) return;
    _clearExitUndo();
    if (departure != null) {
      final idx = _messages.indexOf(departure);
      if (idx >= 0) deleteMessage(idx); // removes + reverts realism + saves
    }
    final id = guest.dbId;
    if (id != null && !_sceneGuestIds.contains(id)) {
      _sceneGuestIds.add(id);
      await _resolveSceneGuestCards();
      await _saveChat();
    }
    _setGuestStatus('${guest.name} is back in the scene.');
    notifyListeners();
  }

  /// Library characters eligible to `/join` this 1:1 scene as a Scene Guest:
  /// every loaded character EXCEPT the current host and anyone already present.
  /// Empty in group mode or before a 1:1 host is set. Drives both the `/join`
  /// name-resolution and the picker dialog's list.
  List<CharacterCard> get joinableGuestCharacters {
    final repo = _characterRepository;
    if (repo == null || _activeCharacter == null || _activeGroup != null) {
      return const [];
    }
    final hostId = _activeCharacter!.dbId;
    final present = _sceneGuestIds.toSet();
    return repo.characters.where((c) {
      final id = c.dbId;
      if (id == null) return false;
      if (hostId != null && id == hostId) return false; // can't invite the host
      if (present.contains(id)) return false; // already in the scene
      return true;
    }).toList();
  }

  /// Library characters eligible to `/join` an active GROUP as a full member:
  /// every loaded character except those already in the cast (excluded by name —
  /// addCharacterToGroup's stable-identity D5 guard is the real backstop). Empty
  /// outside a group. Drives `/join` resolution in group chats.
  List<CharacterCard> get joinableGroupCharacters {
    final repo = _characterRepository;
    if (repo == null || _activeGroup == null) return const [];
    final memberNames = _groupCharacters
        .map((c) => c.name.trim().toLowerCase())
        .toSet();
    return repo.characters
        .where((c) => !memberNames.contains(c.name.trim().toLowerCase()))
        .toList();
  }

  /// Bring an existing library [card] into the scene as a Scene Guest (the
  /// picker's selection handler; same parity-safe enter path as `/create`).
  Future<void> joinSceneGuest(CharacterCard card) =>
      _addGuestWithStatus(displayName: card.name, existing: card);

  /// Bring an existing library [card] in as a FULL participant (realism-bearing).
  ///
  /// In a 1:1 this converts the chat into a group *in place* (host + [card]) by
  /// reusing [forkToGroupChat]; in an existing group it adds the member via
  /// [addCharacterToGroup]. This is the macro path (`/join --full`) that replaces
  /// the separate Fork-to-Group wizard — same underlying machinery, no screen
  /// switch. Requires the group repository (wired from main.dart).
  Future<void> joinFull(CharacterCard card) async {
    final repo = _groupChatRepository;
    if (repo == null) {
      _setGuestStatus('⚠ Group support is unavailable right now.', isError: true);
      return;
    }
    if (_isGenerating) {
      _setGuestStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    if (_activeGroup != null) {
      final ok = await addCharacterToGroup(card, repo);
      if (!ok) {
        // addCharacterToGroup already surfaced a specific reason (e.g. the D5
        // "already in this chat" banner); don't clobber it with a generic one.
        return;
      }
      // Members are copied under fresh UUIDs, so resolve the live member by name
      // before having them make their organic entrance.
      final resolved = groupCharacters.firstWhere(
        (c) => c.name == card.name,
        orElse: () => card,
      );
      await _generateMemberEntrance(
        resolved,
        'enter the scene naturally, reacting to what is happening',
      );
      return;
    }

    // 1:1 → group conversion. Bring EVERYONE currently in the scene along: the
    // host (added by forkToGroupChat) plus every present lite guest — lite NPCs
    // can't exist in a group, so they're promoted to full members rather than
    // dropped. A character who is already a present guest just gets promoted
    // (no fresh entrance); a brand-new arrival makes an organic, LLM-written
    // entrance from the chat so far + their card (mirroring the lite /join flow).
    final present = List<CharacterCard>.from(_sceneGuestCards);
    final cardId = _getCharacterIdFromCard(card);
    final isPresentGuest = present.any(
      (g) => _getCharacterIdFromCard(g) == cardId,
    );

    final additional = <CharacterCard>[
      if (!isPresentGuest) card,
      ...present,
    ];
    final entrances = isPresentGuest
        ? const <String, ({String text, bool creative})>{}
        : {
            cardId: (
              text: 'enter the scene naturally, reacting to what is happening',
              creative: true,
            ),
          };

    await _convertOneToOneToGroup(additional, entrances, repo);
  }

  /// Promote the entire present scene — the host plus every present lite guest —
  /// into a full group, with no new arrival. This is the bare `/join --full`
  /// (and any "make this a group" affordance): it turns a 1:1 that has picked up
  /// lite NPCs into a real group where everyone is a full, realism-bearing member.
  Future<void> promoteSceneToFull() async {
    final repo = _groupChatRepository;
    if (repo == null) {
      _setGuestStatus('⚠ Group support is unavailable right now.', isError: true);
      return;
    }
    if (_isGenerating) {
      _setGuestStatus(
        '⚠ Wait for the current reply to finish first.',
        isError: true,
      );
      return;
    }
    if (_activeGroup != null) return; // already a group
    final present = List<CharacterCard>.from(_sceneGuestCards);
    if (present.isEmpty) {
      _setGuestStatus(
        '⚠ No guests to promote — bring one in with /join --full <name>.',
        isError: true,
      );
      return;
    }
    // No fresh entrance: everyone is already in the scene, they just become full.
    await _convertOneToOneToGroup(
      present,
      const <String, ({String text, bool creative})>{},
      repo,
    );
  }

  /// Shared 1:1→group conversion core used by [joinFull] and
  /// [promoteSceneToFull]. Drops present guests' lite state (they become full
  /// members) and forks the current chat into a group with [additional] members
  /// and any creative [entrances], surfacing a failure banner if it can't.
  Future<void> _convertOneToOneToGroup(
    List<CharacterCard> additional,
    Map<String, ({String text, bool creative})> entrances,
    GroupChatRepository repo,
  ) async {
    // The present guests are becoming full members — drop their lite state so
    // they aren't represented twice once we switch into group mode.
    _sceneGuestIds.clear();

    final group = await forkToGroupChat(additional, repo, entrances: entrances);
    if (group == null) {
      _setGuestStatus(
        '⚠ Could not convert this chat into a group.',
        isError: true,
      );
    }
  }

  /// Have [resolved] (a current group member) make an organic, LLM-written
  /// entrance: force them to speak next under a hidden stage-direction so they
  /// write their own entrance from the chat so far + their card. Shared by the
  /// 1:1→group conversion (via forkToGroupChat) and live `/join --full` / sidebar
  /// adds. Returns true on success. [intent] is sanitized so it cannot break out
  /// of the bracketed directive injection.
  Future<bool> _generateMemberEntrance(
    CharacterCard resolved,
    String intent,
  ) async {
    final safeText = intent
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
      return true;
    } catch (e) {
      debugPrint('[Join:Entrance] ${resolved.name} failed: $e');
      _entranceDirective = null; // don't leak into a later turn
      return false;
    }
  }

  /// Clear a pending picker request (user cancelled or finished picking).
  void dismissGuestPicker() {
    _pendingGuestPickerFilter = null;
    _pendingGuestPickerFull = false;
    notifyListeners();
  }

  ChatCommandHandler? _commandHandler;

  /// Slash-command dispatcher (lazily built). All cross-state mutations route
  /// back here via small callbacks so the handler stays pure and never imports
  /// this god file or any heavy service.
  ChatCommandHandler _ensureCommandHandler() {
    return _commandHandler ??= ChatCommandHandler(
      setExpression: (label) => _expressionService.setManualExpression(label),
      activeCharacterIsSet: () =>
          _activeCharacter != null && _activeGroup == null,
      getSceneGuestCards: () => _sceneGuestCards,
      setPendingGuestDeparture: (name) => _pendingGuestDeparture = name,
      onSystemMessage: (message) =>
          // Surface usage hints / errors as the transient inline banner instead
          // of a saved 'System' chat message (no litter). '⚠' prefix = error.
          _setGuestStatus(message, isError: message.startsWith('⚠')),
      generatePrimaryTurn: () => _generateResponse(GenerationMode.normal),
      createGuest: (name, concept) => _addGuestWithStatus(
        displayName: name,
        mint: (onStatus) => _mintSceneGuest(name, concept, onStatus: onStatus),
      ),
      exitGuest: (guest) async {
        _sceneGuestIds.remove(guest.dbId);
        await _resolveSceneGuestCards();
        await _saveChat();
      },
      getJoinableCharacters: () => joinableGuestCharacters,
      joinGuest: joinSceneGuest,
      joinFull: joinFull,
      promoteScene: promoteSceneToFull,
      requestGuestPicker: (filter, full) {
        _pendingGuestPickerFilter = filter;
        _pendingGuestPickerFull = full;
        notifyListeners();
      },
      runCastScan: runCastDetectionNow,
      speakGuest: speakGuestNow,
      armExitUndo: armSceneGuestExitUndo,
      getGroupMembers: () =>
          _activeGroup != null ? _groupCharacters : const <CharacterCard>[],
      getGroupJoinableCharacters: () => joinableGroupCharacters,
      removeGroupMember: (member) async {
        final repo = _groupChatRepository;
        if (repo == null) return false;
        // Narrate the member's goodbye + arm a deferred-deletion UNDO; the real
        // removal commits when the user continues (mirrors the Lite-NPC exit).
        return exitGroupMember(member, repo);
      },
      speakGroupMember: (member) async {
        // /speak <name> in a full group: force that member to take their turn now
        // (jump the rotation), mirroring the Lite-NPC /speak. Same setNextSpeaker
        // + generate path the goodbye narration uses, minus the removal/directive.
        if (_activeGroup == null || _isGenerating) return;
        _groupManager?.setNextSpeaker(member);
        await _generateResponse(GenerationMode.normal);
      },
      isGroupTurnOrderRandom: () => isGroupTurnOrderRandom,
      setGroupTurnOrder: (random, customOrder) =>
          setGroupTurnOrder(random, customOrder),
    );
  }

  /// Whether Scene Guests automatically chime in after the primary's turn.
  /// Phase 1 keeps this in-memory (default ON) rather than persisted — there is
  /// no settings UI yet; a public setter lets callers toggle it.
  bool autoChimeEnabled = true;

  SceneGuestDirector? _sceneGuestDirector;

  /// Auto chime-in director (lazily built). Pure leaf — all cross-state routes
  /// back via callbacks so it never imports this god file. Reuses the existing
  /// `LlmEvalEngine` fire/strip/extract surface for its relevance gate (no new
  /// LLM-firing path) and only triggers parity-safe guest turns.
  SceneGuestDirector _ensureSceneGuestDirector() {
    return _sceneGuestDirector ??= SceneGuestDirector(
      getSceneGuestCards: () => _sceneGuestCards,
      generateGuestTurn: generateGuestTurn,
      getLatestAssistantText: () {
        for (final m in _messages.reversed) {
          if (!m.isUser && m.sender != 'System') return m.displayText;
        }
        return '';
      },
      fireGateEval: (prompt) => _fireLLMEval(prompt),
      stripThinkBlocks: _stripThinkBlocks,
      extractJsonBool: _extractJsonBool,
      getHostName: () => _activeCharacter?.name ?? 'the character',
      isEnabled: () => autoChimeEnabled,
    );
  }

  // ── Scene Guest cast detection (Phase 2) ────────────────────────────────
  // Periodically (not every turn) scans the primary's recent narration in a
  // 1:1 chat for a newly-introduced, recurring, named side character and offers
  // to promote it to a Scene Guest. Detection only reads text + triggers the
  // existing parity-safe mint/enter flow, so it adds ZERO Realism/Needs work.

  /// Whether the periodic cast-detection scan runs. In-memory (default ON),
  /// mirroring [autoChimeEnabled].
  bool sceneDetectionEnabled = true;

  /// Run a detection scan every this-many primary (user) turns. Small and
  /// constant so the eval is infrequent and turns stay cheap.
  static const int _castScanInterval = 4;

  /// Primary turns since the last cast-detection scan (sibling to the facts
  /// counter [_userMessagesSinceLastPeriodicEval]; zeroed at the same Scene
  /// Guest reset sites alongside `_pendingGuestDeparture = null`).
  int _userMessagesSinceLastCastScan = 0;

  /// A detected candidate awaiting the user's accept/ignore choice. Surfaced to
  /// the chat UI exactly like the Chance Time wheel's pending flag: set + clear
  /// here with [notifyListeners]; the page observes it and shows the popup once.
  DetectedCharacter? _pendingGuestDetection;

  /// The candidate the popup should show (null = nothing pending).
  DetectedCharacter? get pendingGuestDetection => _pendingGuestDetection;

  /// Names already offered (whether accepted or ignored) this session,
  /// lower-cased, so the same character is never re-offered. Cleared at the
  /// Scene Guest reset sites.
  final Set<String> _offeredOrIgnoredGuestNames = {};

  CastDetector? _castDetector;

  /// Cast detector (lazily built). Pure leaf — all cross-state routes back via
  /// callbacks so it never imports this god file. Reuses the existing
  /// `LlmEvalEngine` fire/strip surface (no new LLM-firing path).
  CastDetector _ensureCastDetector() {
    return _castDetector ??= CastDetector(
      getRecentPrimaryTexts: () {
        // HOST narration only — exclude user, System, AND Scene Guest messages.
        // The detector prompt says "read <host>'s narration", so feeding it a
        // guest's lines would let a guest "introduce" a character or get a guest
        // misattributed to the host.
        final out = <String>[];
        for (final m in _messages.reversed) {
          if (!m.isUser &&
              m.sender != 'System' &&
              !_isGuestAuthoredMessage(m)) {
            out.add(m.displayText);
          }
          if (out.length >= 6) break;
        }
        return out.reversed.toList();
      },
      fireLLMEval: (prompt) => _fireLLMEval(prompt),
      stripThinkBlocks: _stripThinkBlocks,
      getHostName: () => _activeCharacter?.name ?? '',
      getUserName: () => _userPersonaService.persona.name,
      getSceneGuestNames: () => _sceneGuestCards.map((g) => g.name).toList(),
      getOfferedOrIgnoredNames: () => _offeredOrIgnoredGuestNames,
    );
  }

  /// Promote the pending detected character to a real Scene Guest via the
  /// EXISTING mint+add+enter path (same as `/create`). Seeds the guest from the
  /// detected name + descriptor (as concept). Surfaces errors like `/create`.
  Future<void> acceptDetectedGuest() async {
    final detected = _pendingGuestDetection;
    if (detected == null) return;
    _pendingGuestDetection = null;
    _offeredOrIgnoredGuestNames.add(detected.name.trim().toLowerCase());
    notifyListeners();

    await _addGuestWithStatus(
      displayName: detected.name,
      mint: (onStatus) =>
          _mintSceneGuest(detected.name, detected.descriptor, onStatus: onStatus),
    );
  }

  /// Decline the pending detection; the name is remembered so it is never
  /// re-offered this session.
  void dismissDetectedGuest() {
    final detected = _pendingGuestDetection;
    if (detected != null) {
      _offeredOrIgnoredGuestNames.add(detected.name.trim().toLowerCase());
    }
    _pendingGuestDetection = null;
    notifyListeners();
  }

  /// Mint a Scene Guest (Lite NPC) via the extracted factory (gen + persist),
  /// using the active backend + the host character for scene context.
  Future<GuestMintResult> _mintSceneGuest(
    String name,
    String concept, {
    void Function(String step)? onStatus,
  }) async {
    final repo = _characterRepository;
    if (repo == null) return const GuestMintResult.failure('no repository');
    return SceneGuestFactory(repo, _storageService).mint(
      name: name,
      concept: concept,
      sceneGrounding: _buildGuestGrounding(name),
      llm: testLlmServiceOverride ?? _llmProvider?.activeService,
      host: _activeCharacter,
      onStatus: onStatus,
    );
  }

  /// Collect the in-chat narration that portrays [name] so a minted Scene Guest
  /// is built from how the character actually appeared — not invented from a
  /// bare name (which produced cards with nothing in common with the scene).
  /// Returns the most recent lines that mention the guest (by their first name,
  /// word-boundary), bounded for tokens; empty when the name hasn't come up yet.
  String _buildGuestGrounding(String name) {
    final first = name.trim().split(RegExp(r'\s+')).first;
    if (first.length < 2) return '';
    // If the guest's first name overlaps the host's or the user's name, the
    // name-matched excerpts are dominated by the host/user, and grounding would
    // build the guest FROM the host's portrayal (the "guest IS the host" bug).
    // Skip grounding in that case and let concept-only generation handle it.
    final firstLc = first.toLowerCase();
    final hostFirst =
        (_activeCharacter?.name ?? '').trim().split(RegExp(r'\s+')).first.toLowerCase();
    final userFirst = _userPersonaService.persona.name
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    if (firstLc == hostFirst || firstLc == userFirst) return '';
    final re = RegExp(r'\b' + RegExp.escape(first) + r'\b', caseSensitive: false);
    final hits = <String>[];
    for (final m in _messages) {
      if (m.sender == 'System') continue;
      final t = m.displayText.trim();
      if (t.isEmpty || !re.hasMatch(t)) continue;
      hits.add(t);
    }
    if (hits.isEmpty) return '';
    final recent = hits.length > 10 ? hits.sublist(hits.length - 10) : hits;
    var joined = recent.join('\n---\n');
    const cap = 4000;
    if (joined.length > cap) joined = joined.substring(joined.length - cap);
    return joined;
  }

  /// True when the active 1:1 scene changed (chat/character/session switched)
  /// or the service was disposed since [token] (a `_currentSessionId` snapshot)
  /// was captured. Fire-and-forget guest async work must bail — no state
  /// mutation, no DB, no UI signal — when this returns true after an `await`.
  bool _sceneChanged(String? token) => _disposed || _currentSessionId != token;

  /// Re-resolve `_sceneGuestCards` from `_sceneGuestIds` using the repository.
  /// Called whenever the id list changes or on session load. Drops ids that no
  /// longer resolve (e.g. the guest character was deleted from the library).
  ///
  /// IMPORTANT: a guest is NOT scenario-stripped on its shared library card here
  /// (getCharacterCardById returns the repository's live reference — mutating it
  /// would corrupt the character for when it's opened as a normal host). The
  /// guest's scenario is instead blanked only in the prompt at guest-turn time
  /// (see `guestSpeaker != null` in `_generateResponse`).
  Future<void> _resolveSceneGuestCards() async {
    if (_disposed) return;
    final repo = _characterRepository;
    if (repo == null) return;
    // Never run two passes at once: each awaits per-id DB reads and then mutates
    // the shared id/card lists, so overlapping passes could read a half-mutated
    // list or race the DB. Coalesce concurrent requests into one trailing re-run.
    if (_resolvingSceneGuests) {
      _sceneGuestsResolvePending = true;
      return;
    }
    final token = _currentSessionId;
    _resolvingSceneGuests = true;
    try {
      do {
        _sceneGuestsResolvePending = false;
        final resolved = <CharacterCard>[];
        final validIds = <String>[];
        for (final id in List<String>.from(_sceneGuestIds)) {
          if (_sceneChanged(token)) return; // disposed or chat switched mid-pass
          final card = await repo.getCharacterCardById(id);
          if (card != null) {
            resolved.add(card);
            validIds.add(id);
          }
        }
        if (_sceneChanged(token)) return;
        _sceneGuestIds
          ..clear()
          ..addAll(validIds);
        _sceneGuestCards
          ..clear()
          ..addAll(resolved);
        notifyListeners();
      } while (_sceneGuestsResolvePending && !_disposed);
    } finally {
      _resolvingSceneGuests = false;
    }
  }

  bool _resolvingSceneGuests = false;
  bool _sceneGuestsResolvePending = false;

  /// True when [charId] (a stable charId from `_getCharacterIdFromCard`)
  /// belongs to a current Scene Guest. Used to route per-guest evolution
  /// persistence into the 1:1 guest blob instead of the active character's
  /// session columns, and to clear only guest entries from the shared evolved
  /// maps on reset.
  bool _isSceneGuestCharId(String charId) =>
      _sceneGuestCards.any((g) => _getCharacterIdFromCard(g) == charId);

  /// Resolve the Scene Guest card that authored message [m], or null when [m] is
  /// a host / group / system / user message. Used by regenerate + swipe so a
  /// guest message stays a parity-safe GUEST turn (no Realism/Needs, spoken as
  /// the guest) instead of being regenerated as the host. Guests are 1:1-only,
  /// so this is always null in group mode.
  /// True when [m] was authored by a Scene Guest rather than the host — decided
  /// by the stable characterId stamped at guest-turn time, NOT by live scene
  /// membership or sender name. Stays correct after the guest has `/exit`-ed and
  /// when a guest shares the host's display name (the name fallback previously
  /// here could misclassify a host message as a guest's). Host/user/system/group
  /// messages → false.
  bool _isGuestAuthoredMessage(ChatMessage m) {
    if (_activeGroup != null || m.isUser || m.sender == 'System') return false;
    final cid = m.characterId;
    if (cid == null || cid.isEmpty) return false; // legacy / host-authored
    final hostId = _activeCharacter != null
        ? _getCharacterIdFromCard(_activeCharacter!)
        : null;
    return cid != hostId;
  }

  /// The PRESENT Scene Guest card that authored [m] (to regenerate/swipe as), or
  /// null when [m] is host-authored OR the authoring guest has left the scene.
  /// Use [_isGuestAuthoredMessage] to tell "host" apart from "departed guest".
  CharacterCard? _sceneGuestForMessage(ChatMessage m) {
    if (!_isGuestAuthoredMessage(m)) return null;
    final cid = m.characterId;
    for (final g in _sceneGuestCards) {
      if (_getCharacterIdFromCard(g) == cid) return g;
    }
    return null; // authored by a guest who is no longer present
  }

  /// Drop all per-guest Character Evolution state for the current 1:1 context so
  /// it never leaks across chats/characters. Removes the guests' entries from
  /// the SHARED evolved maps (keyed by the tracked participation-count keys) and
  /// clears the participation counts. Mirrored at every `_sceneGuestIds.clear()`
  /// reset site (keep reset blocks in sync).
  void _clearSceneGuestEvolution() {
    for (final charId in _guestEvolutionCounts.keys) {
      _evolvedPersonalities.remove(charId);
      _evolvedScenarios.remove(charId);
    }
    _guestEvolutionCounts.clear();
  }

  /// Generate a turn spoken by a Scene Guest (Lite NPC) inside a 1:1 chat.
  ///
  /// Reuses the normal generation engine with the guest as the speaker. Carries
  /// NO Realism Engine / Needs work (the guest turn is parity-safe — see the
  /// `guestSpeaker == null` guards in `_generateResponse`).
  ///
  /// After the turn finalizes, runs the per-guest Character Evolution check
  /// (Phase 3): the guest's participation count advances and, on the same
  /// `evolutionInterval` cadence a normal character uses, the existing
  /// EvolutionService evolves THIS guest (no Realism/Needs, no effect on the
  /// active character's evolution state).
  /// Common Scene Guest "enter" tail: register the guest's dbId, re-resolve the
  /// resolved-card list, persist the session, then have the guest speak its
  /// entrance via the parity-safe guest-turn path. Shared by `/create`,
  /// `/join`, and the cast-detection accept flow so there is exactly ONE enter
  /// path (no duplicated add/resolve/save/generate logic).
  Future<void> _enterSceneGuest(CharacterCard guest) async {
    if (guest.dbId != null) _sceneGuestIds.add(guest.dbId!);
    await _resolveSceneGuestCards();
    await _saveChat();
    await generateGuestTurn(guest);
  }

  /// Update the transient Scene Guest status line (the inline banner). [sticky]
  /// keeps it shown until the next update (for in-progress steps); otherwise it
  /// auto-clears after a few seconds (errors linger a little longer).
  void _setGuestStatus(String? msg, {bool isError = false, bool sticky = false}) {
    _guestStatusClearTimer?.cancel();
    _guestStatusClearTimer = null;
    _guestActivityStatus = msg;
    _guestActivityIsError = isError;
    notifyListeners();
    if (msg != null && !sticky) {
      _guestStatusClearTimer = Timer(Duration(seconds: isError ? 6 : 3), () {
        _guestActivityStatus = null;
        _guestActivityIsError = false;
        notifyListeners();
      });
    }
  }

  /// Clear the transient Scene Guest banner/busy/evict state. Called at every
  /// scene-guest reset site (context switch / new chat / group) and on dispose
  /// so nothing leaks across chats. Does not notify (callers already do).
  void _resetGuestActivityState() {
    _guestStatusClearTimer?.cancel();
    _guestStatusClearTimer = null;
    _guestActivityStatus = null;
    _guestActivityIsError = false;
    _guestBusy = false;
    _guestAvatarEvictPath = null;
    _clearExitUndo();
  }

  /// Single entry point for adding a Scene Guest with a busy guard + one live,
  /// in-place status line (no saved 'System' chat-message litter). Used by
  /// `/create`, `/join`, the picker, and cast-detection accept. [existing] joins
  /// a library card directly; otherwise [mint] generates one first. A background
  /// portrait kicks off after the guest enters.
  Future<void> _addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) async {
    // Don't race another creation OR an in-flight turn (the mint runs a separate
    // LLM call that doesn't set _isGenerating).
    if (_guestBusy || _isGenerating) {
      _setGuestStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    // Reject a duplicate name when MINTING a new guest (join already excludes
    // anyone present). Two same-named guests make /exit, chime-in targeting, and
    // the host "do not voice: X, X" injection ambiguous.
    if (existing == null) {
      final wanted = displayName.trim().toLowerCase();
      if (_sceneGuestCards.any((g) => g.name.trim().toLowerCase() == wanted)) {
        _setGuestStatus('"$displayName" is already in the scene.', isError: true);
        return;
      }
    }
    final token = _currentSessionId;
    _guestBusy = true;
    notifyListeners();
    try {
      CharacterCard card;
      if (existing != null) {
        card = existing;
        _setGuestStatus('${card.name} is joining the scene…', sticky: true);
      } else {
        _setGuestStatus('Creating "$displayName"…', sticky: true);
        // Surface each generation sub-step ("$name · Running interview…") so the
        // banner reflects progress instead of one static spinner.
        final result = await mint!((step) {
          if (_sceneChanged(token)) return; // don't paint into another chat
          _setGuestStatus('$displayName · $step', sticky: true);
        });
        if (_sceneChanged(token)) return; // user switched chats mid-generation
        if (!result.ok) {
          _setGuestStatus(
            'Couldn’t create "$displayName": ${result.error}',
            isError: true,
          );
          return;
        }
        card = result.card!;
      }
      _setGuestStatus('${card.name} is making an entrance…', sticky: true);
      await _enterSceneGuest(card);
      if (_sceneChanged(token)) return; // switched during the entrance turn
      _setGuestStatus('${card.name} joined the scene'); // auto-clears
      _maybeGenerateGuestPortrait(card); // background; never blocks the entrance
    } finally {
      // Only clear busy if we still own this scene — a context switch already
      // reset it (and may have started new work we must not clobber).
      if (!_sceneChanged(token)) {
        _guestBusy = false;
        notifyListeners();
      }
    }
  }

  /// Background portrait for a freshly-added guest: if an image backend is
  /// configured, generate art from the card's description and write it onto the
  /// guest's card PNG, then signal the UI to refresh that avatar. Fire-and-forget
  /// — the guest is already in the scene with an initials avatar; this just fills
  /// the art in when ready. ZERO Realism/Needs. No-op without an image backend.
  void _maybeGenerateGuestPortrait(CharacterCard card) {
    final igs = _imageGenService;
    final cardPath = card.imagePath;
    final desc = card.description.trim();
    if (igs == null || !igs.isConfigured) return;
    if (cardPath == null || cardPath.isEmpty || desc.isEmpty) return;
    final prompt = desc.length > 500 ? desc.substring(0, 500) : desc;
    final token = _currentSessionId;
    final dbId = card.dbId;
    unawaited(() async {
      String? tmpPath;
      try {
        final bytes = await igs.generateImage(prompt: prompt, isPortrait: true);
        if (bytes == null || bytes.isEmpty) return;
        // Image gen is slow: don't bake art for a guest that has since left the
        // scene / had its card deleted, or into a chat the user already left.
        if (_sceneChanged(token)) return;
        if (dbId != null && !_sceneGuestIds.contains(dbId)) return;
        // saveCardAsPng takes a SOURCE IMAGE PATH (not bytes), so stage the
        // generated art to a per-invocation temp file (unique so two portrait
        // generations can't corrupt each other mid-write), then bake it in.
        tmpPath = path.join(
          Directory.systemTemp.path,
          'fp_guest_portrait_${dbId ?? card.name.hashCode}_'
              '${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await File(tmpPath).writeAsBytes(bytes);
        await V2CardService().saveCardAsPng(card, cardPath, tmpPath);
        if (_sceneChanged(token)) return; // re-check after the slow write
        _guestAvatarEvictPath = cardPath; // UI evicts the stale cached image
        notifyListeners();
      } catch (e) {
        debugPrint('[SceneGuest] portrait generation failed: $e');
      } finally {
        if (tmpPath != null) {
          try {
            final f = File(tmpPath);
            if (f.existsSync()) await f.delete();
          } catch (_) {}
        }
      }
    }());
  }

  /// Force a present Scene Guest to take a turn NOW (the `/speak` macro),
  /// bypassing the auto chime-in heuristic + LLM gate. Parity-safe — it runs the
  /// same `generateGuestTurn` (zero Realism/Needs). Busy-guarded like the create
  /// flow so it can't race a user turn / another guest creation, and
  /// context-guarded so a chat switch mid-turn can't leave `_guestBusy` stuck.
  Future<void> speakGuestNow(CharacterCard guest) async {
    if (_activeGroup != null) return;
    if (_isGenerating || _guestBusy) {
      _setGuestStatus('Busy — try again in a moment.', isError: true);
      return;
    }
    final token = _currentSessionId;
    _guestBusy = true;
    notifyListeners();
    try {
      await generateGuestTurn(guest);
    } finally {
      if (!_sceneChanged(token)) {
        _guestBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> generateGuestTurn(CharacterCard guest) async {
    await _generateResponse(GenerationMode.normal, guestSpeaker: guest);
    _maybeEvolveGuest(guest);
    // Phase 4: give the guest EPISODIC MEMORY. The host's embed stays gated
    // behind `guestSpeaker == null` in `_generateResponse`; here we embed the
    // just-finished exchange under the GUEST's own id (the same id the guest
    // retrieves under in `_getMemorySourceIds`) by REUSING the host embed path.
    // Fire-and-forget; ZERO Realism/Needs. So a later guest turn — even in a
    // different chat — recalls what happened.
    _maybeEmbedMessages(characterIdOverride: _getCharacterIdFromCard(guest));
  }

  /// Per-guest evolution cadence + trigger (Phase 3). Mirrors the active-char
  /// scheme in `_maybeRunPeriodicEvals` (count vs `evolutionInterval`) but keyed
  /// on the guest's own participation count, and routes through the SAME
  /// EvolutionService via `triggerCharacterEvolution(targetCharacter:)`. The
  /// evolved text is written into the shared evolved maps (so it applies on the
  /// guest's next turn through `_getEffectivePersonality`) and persisted into
  /// the guest blob by the evolution persist callback. Fire-and-forget so it
  /// never blocks the turn; does ZERO Realism/Needs work.
  void _maybeEvolveGuest(CharacterCard guest) {
    if (!_storageService.memorySettings.characterEvolutionEnabled) return;
    // Shared busy guard — one evolution (host or guest) at a time.
    if (_isEvolvingCharacter) return;
    final charId = _getCharacterIdFromCard(guest);
    final interval = _storageService.memorySettings.evolutionInterval;
    if (interval <= 0) return;
    final count = (_guestEvolutionCounts[charId] ?? 0) + 1;
    _guestEvolutionCounts[charId] = count;
    if (count % interval != 0) {
      // Persist the bumped participation count now — on a non-evolving turn
      // nothing else saves it, so on app close the guest's cadence would reset.
      unawaited(_saveChat());
      return; // not due yet on this cadence
    }
    debugPrint(
      '[SceneGuest] ▶ Evolving guest ${guest.name} '
      '(charId=$charId, participation=$count, every $interval)',
    );
    // Reuse the existing evolution service + persist/layering. No parallel path.
    _evolutionService.triggerCharacterEvolution(targetCharacter: guest);
  }

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

  // ── Web token broadcast ──
  // External consumers (the web server's StreamHub) listen to this for real-time token streaming.
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

  /// The group member id (`_getCharacterIdFromCard`) whose realism state is being
  /// processed for the turn currently generating. Set the moment the speaker is
  /// picked in `_generateResponse` and cleared in its `finally`, so every realism
  /// consumer (prompt injection, decay, post-gen) keys on the character actually
  /// speaking — `nextCharacter` points at the *upcoming* speaker and is null for
  /// random turn order, so it cannot be that signal. Null outside a turn (the
  /// pre-pick window keeps its prior nextCharacter-based behaviour).
  String? _turnSpeakerIdForRealism;

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

  /// Central macro resolver for prompt template expansion.
  late final _macroResolver = MacroResolver();

  /// Regex matching any `{{macro}}` or `{{macro::args}}` pattern.
  /// Used to detect stray unresolved macros in chat history.
  static final _macroPattern = RegExp(r'\{\{(\w+)(?:::(.+?))?\}\}');

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

  /// New central composer for the full speaker-internal realism snapshot.
  /// Replaces the previous loose concatenation of the individual builders.
  /// This gives the model one clearly grouped, number-first view of relationship,
  /// emotion, time, needs (with x/100), behavioral anchors, nsfw state, etc.
  late final _realismStateInjection = RealismStateInjection(
    relationshipInjection: _relationshipInjection,
    emotionInjection: _emotionInjection,
    timeInjection: _timeInjection,
    behavioralInjection: _behavioralInjection,
    nsfwInjection: _nsfwInjection,
    needsInjection: _needsInjection,
    needsSimulation: _needsSimulation,
    relationshipService: _relationshipService,
    timeService: _timeService,
    nsfwService: _nsfwService,
    getRealismEnabled: () => _realismEnabled,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getActiveCharacter: () => _activeCharacter,
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
    getKoboldThinkingModel: () =>
        _storageService.backendSettings.koboldThinkingModel,
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
    getMacroResolver: () => _macroResolver,
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
  // The facts cadence now uses its dedicated _userMessagesSinceLastPeriodicEval vs autoPersonaInterval
  // (god thin coordinator decides; leaf has no cadence logic).
  // God late final (after _summaryService) + thins/delegates at *every* prior call site (the one in
  // _runPeriodicEvalsInSequence and the guard/flag use) with *full excision* of the moved bodies from god.
  // 0 @Deprecated shims. 0 new god private _ methods (thins as the public surface; live `grep -c '^\s*void _[a-zA-Z]' lib/services/chat_service.dart` *must stay exactly 15* after *every* edit + final; +1 late final + thins/calls + reset comment syncs only).
  // Stateless/prompt-only (no owned reset/seed/load state for processing — god owns the scalars/flags/cadence; no reset calls needed on leaf).
  // God reset "keep blocks in sync" comments expanded at *all* ~15+ documented sites (full prior+current list + fact_extraction (stateless or prompt-only; no reset calls needed) + evolution_service (stateless or prompt-only; no reset calls needed) + realism_verification (stateless or prompt-only; no reset calls needed) + "incomplete zeroing... now complete (see CLAUDE.md)"; both startNew branches explicit; cross-refs e.g. setActiveCharacter:1572).
  // The facts cadence counter (_userMessagesSinceLastPeriodicEval) is zeroed at every one of these sites (in addition to the flags) to keep its schedule in sync after chat switches / 0-session / group entry ("incomplete zeroing of secondary config on group/0-session/new-chat now complete (see CLAUDE.md)"). Character-evolution cadence is driven separately by _characterEvolutionCount vs evolutionInterval (no side-counter), so it needs no zeroing here.
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
  // Cadence decision (live chat user-message count vs persisted _characterEvolutionCount + evolutionInterval) lives
  // in the god _maybeRunPeriodicEvals thin coordinator (plus the run sequence thin); evolution
  // leaf is purely trigger/extract/LLM/persist/layering. God late final (after _factExtraction) + thins/delegates at *every* prior call site for
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
  // Evolution cadence decision uses live chat user-message count + persisted _characterEvolutionCount vs evolutionInterval (robust; no side-counter).
  // The facts cadence counter (_userMessagesSinceLastPeriodicEval) is still zeroed on the hygiene sites to keep its schedule in sync after context switches.
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
      // Phase 3 — Scene Guest evolution. The target is a 1:1 guest, not the
      // active character: store the evolved text in the shared maps (so the
      // existing layering applies on the guest's next turn) + the per-guest
      // count, then persist into the guest blob via _saveChat. We deliberately
      // do NOT touch the active character's session columns or
      // _characterEvolutionCount here (no perturbation of the host's state).
      if (_isSceneGuestCharId(charId)) {
        // `count` here is the EvolutionService's generation count (evolved N
        // times). For guests we drive cadence off the participation counter in
        // `_guestEvolutionCounts` (set in `_maybeEvolveGuest`), so we leave it
        // untouched and only persist the evolved text + that participation
        // count via the guest blob.
        _evolvedPersonalities[charId] = pers;
        _evolvedScenarios[charId] = scen;
        notifyListeners();
        await _saveChat();
        return;
      }
      if (_currentSessionId != null) {
        if (_activeGroup != null) {
          // GROUP: only the PERSONALITY evolves per-character. The scenario is the
          // ONE shared scene — evolving it per-character drifts the story (each
          // member ends up in a slightly different scenario), so it is left to the
          // group's single shared scenario and not written per-character here.
          final session = await _db.getSessionById(_currentSessionId!);
          if (session != null) {
            final personalities = _tryParseJsonMap(
              session.groupEvolvedPersonalities,
            );
            personalities[charId] = pers;
            await _db.patchSession(
              SessionsCompanion(
                id: drift.Value(_currentSessionId!),
                groupEvolvedPersonalities: drift.Value(
                  jsonEncode(personalities),
                ),
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
      // In a group the scenario is shared (not per-character) — see the persist
      // branch above; don't stamp a per-character evolved scenario that would
      // drift the story. 1:1 keeps its evolved scenario.
      if (_activeGroup == null) {
        _evolvedScenarios[charId] = scen;
      }
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
  // _evaluateRealismForUpcomingSpeaker ; _waitForTtsThenContinue + drain
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

  /// Inter-call delay used when staggering the multi-call realism evaluations.
  /// Kept in the class body (not the realism-evals extension) because the
  /// periodic-eval coordinator in this file references it directly; extension
  /// statics aren't visible unqualified to the host type.
  static const _kEvalDispatchStagger = Duration(milliseconds: 50);

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

  /// The unified ordered cast of speakers for the active chat, regardless of
  /// mode. This is the single roster the UI reads instead of branching on
  /// `isGroupMode` between `activeCharacter`, `groupCharacters`, and
  /// `sceneGuestCards`:
  ///   - Group chat → each group member, in turn order (no distinct host).
  ///   - 1:1 / NPC chat → the host (`cast[0]`, realism-bearing) followed by any
  ///     present Scene Guests (lite NPCs, realism off).
  /// Empty only when no chat is loaded.
  List<ChatParticipant> get cast {
    if (isGroupMode) {
      return [
        for (final c in groupCharacters)
          ChatParticipant(card: c, isHost: false),
      ];
    }
    final host = _activeCharacter;
    return [
      if (host != null) ChatParticipant(card: host, isHost: true),
      for (final g in _sceneGuestCards) ChatParticipant(card: g, isHost: false),
    ];
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
    if (identical(_characterRepository, repo)) return;
    _characterRepository?.removeListener(_onCharacterLibraryChanged);
    _characterRepository = repo;
    _characterRepository!.addListener(_onCharacterLibraryChanged);
  }

  /// Silently prune Scene Guests whose library card no longer exists. Deleting a
  /// character PNG is a deliberate user action, so a deleted guest is dropped
  /// from the open scene with NO `/exit` narration — `_resolveSceneGuestCards`
  /// removes any id that no longer resolves. Self-heals the "deleted card but
  /// still treated as present" case (e.g. cast detection skipping a re-narrated
  /// character because the stale guest was still in the scene list).
  void _onCharacterLibraryChanged() {
    if (_disposed || _guestBusy || _sceneGuestIds.isEmpty) return;
    // Defer out of the repository's notify callback so we never start a DB read
    // from inside its in-progress write/transaction; re-check guards (and that
    // the chat hasn't switched) on the microtask. _resolveSceneGuestCards also
    // self-guards on the token, so a stale resolve can't write the wrong chat.
    final token = _currentSessionId;
    scheduleMicrotask(() {
      if (_sceneChanged(token) || _guestBusy || _sceneGuestIds.isEmpty) return;
      _resolveSceneGuestCards();
    });
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
    final safeUserName = userName.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();

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
    // ALWAYS establish the user's identity by NAME — even with no persona text.
    // Otherwise the model only sees "$userName:" history labels and invents a
    // generic descriptor ("the boy"/"the girl") for the human. (Previously this
    // returned '' entirely when the persona had no description.)
    if (personaText.isNotEmpty) {
      final safePersonaText = personaText
          .replaceAll(RegExp(r'[\n\r"]'), ' ')
          .trim();
      buf.writeln("$safeUserName's Persona: $safePersonaText");
    } else {
      buf.writeln('$safeUserName is the human you are talking with.');
    }

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
    // The model HAS the name above — nudge it to actually use it instead of
    // reaching for a generic epithet for the human.
    buf.writeln(
      'Always refer to $safeUserName by name; never substitute a generic '
      'descriptor like "the boy", "the girl", or "the user".',
    );
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

  /// Set the ImageGenService after construction (for background Scene Guest
  /// portraits). Optional — when absent or unconfigured, guests just keep their
  /// initials avatar.
  void setImageGenService(ImageGenService service) {
    _imageGenService = service;
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
        Future.delayed(
          _kEvalDispatchStagger,
          () => _evaluateRelationshipCall(),
        ),
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
          Future.delayed(
            _kEvalDispatchStagger,
            () => _evaluateEmotionalStateCall(),
          ),
          Future.delayed(
            _kEvalDispatchStagger * 2,
            () => _evaluatePhysicalStateCall(),
          ),
          Future.delayed(
            _kEvalDispatchStagger * 3,
            () => _evaluateNarrativeCall(),
          ),
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
    return _macroResolver.resolve(
      msg,
      MacroContext(
        userName: _userPersonaService.persona.name,
        characterName: character.name,
      ),
      section: 'firstMessage',
    );
  }

  Future<void> sendMessage(String text) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        text.trim().isEmpty) {
      return;
    }
    // Don't let a user turn start while forked-in entrances are still playing —
    // it would race the one-shot entrance directive / turn positioning.
    if (_entrancesInFlight) return;
    // Likewise, don't race an in-flight Scene Guest creation/entrance (the mint
    // runs a separate LLM call that doesn't set _isGenerating).
    if (_guestBusy) return;
    clearSuggestions();

    // ── Slash Command Handling (delegated to leaf) ──────────────────────
    final trimmed = text.trim();
    if (trimmed.startsWith('/') && _characterRepository != null) {
      final handled = await _ensureCommandHandler().handle(trimmed);
      if (handled) return;
      // Unknown command — fall through and send as a normal message.
    }

    // In observer mode, route to sendDirectorNote instead
    if (_observerMode && _activeGroup != null) {
      await sendDirectorNote(text);
      return;
    }

    // Sending a real message ends the /exit undo window. A pending full-member
    // exit commits now (real removal + any collapse to a 1:1) so this turn runs
    // in the settled cast; lite-guest undo state is just cleared.
    await _commitPendingMemberExit();
    _clearExitUndo();

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
    if (_realismActiveThisMode) {
      if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
        preTurnVector = Map<String, int>.from(_needsSimulation.vector);
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['needs_pre_turn_vector'] = preTurnVector;
      }

      _applyMoodDecay();
      // Needs decay for 1:1 always here. For group non-observer, speaker-specific decay
      // (respecting the actual picked speaker for random turn order) is applied inside
      // _evaluateRealismForUpcomingSpeaker after _pickNextGroupCharacter has run.
      if (_activeGroup == null || _observerMode || !_needsSimEnabled) {
        _needsSimulation.tickDecay();
      } else {
        // Group non-obs + needs on: decay is applied per-speaker inside the
        // single eval path (_evaluateRealismForUpcomingSpeaker).
      }
      _nsfwService.decrementCooldownIfActive();

      // Single-path bridge: realism evaluation now runs inside _generateResponse
      // for EVERY speaker (1:1 host or group member) via
      // _evaluateRealismForUpcomingSpeaker.
      //
      // No cast-store mirror for the 1:1 host: its scalar fields are already the
      // canonical realism store (loaded by loadSession, decayed just above), and the
      // per-character _groupRealism map is group-only — its writes no-op when
      // _activeGroup == null. Mirroring was a no-op, and the eval path deliberately
      // does NOT reload the host from that empty map (doing so reset
      // bond/trust/emotion/needs to defaults). See _evaluateRealismForUpcomingSpeaker.
      if (_activeGroup == null && _activeCharacter != null) {
        // Run the SINGLE eval path for the host now — on a fresh user turn only.
        // (Regen/continue call _generateResponse directly, bypassing this, so the
        // host is not re-evaluated; cancellation is caught by the check below,
        // before generation — preserving the cancel-aborts-generation escape.)
        await _evaluateRealismForUpcomingSpeaker(_activeCharacter!);
      }
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
    // Per-message needs-delta chips are attached inside _generateResponse (via
    // _attachNeedsDeltaChipToLastMessage) so EVERY speaker gets them — group
    // auto-advance, /speak and chime-ins reach _generateResponse but never this
    // sendMessage scope, which is why only the first responder used to show
    // chips. preTurnVector is still stamped above as the message's baseline.

    // ── Scene Guests: auto chime-in ─────────────────────────────────────────
    // The primary 1:1 turn is now 100% finalized (response + chip/realism block
    // above). Let the director decide which guest(s) speak next. Shared with
    // regenerateMainCharacter() so the re-chime gate is identical after a regen.
    await _maybeRunSceneGuestChimeIns(userText: text);
  }

  /// Run the Scene Guest director's chime-in gate after a finalized primary/host
  /// turn: it decides which present guest(s) (if any) speak next, each via the
  /// parity-safe [generateGuestTurn]. Shared by the normal send path and the
  /// "regenerate the main character beneath a guest reply" path so the re-chime
  /// decision (mention / relevance) is byte-for-byte identical in both.
  ///
  /// No-op in group chats, mid-generation, during entrances, or with no guests
  /// present. Each gate eval + guest turn is a slow LLM call, so it bails if the
  /// user switches chats / the scene changes (so guests never speak into the
  /// wrong conversation).
  Future<void> _maybeRunSceneGuestChimeIns({required String userText}) async {
    if (_activeGroup != null ||
        _sceneGuestCards.isEmpty ||
        _isGenerating ||
        _entrancesInFlight) {
      return;
    }
    final primaryResponse = _messages.isNotEmpty && !_messages.last.isUser
        ? _messages.last.displayText
        : '';
    final token = _currentSessionId;
    await _ensureSceneGuestDirector().runChimeIns(
      userText: userText,
      primaryResponse: primaryResponse,
      isContextValid: () => !_sceneChanged(token) && _activeGroup == null,
    );
  }

  /// Index of the most recent host (main character) message that is buried only
  /// under Scene Guest (Lite NPC) chime-in replies — i.e. the tail of the chat
  /// is one or more guest messages sitting directly on top of it. Returns null
  /// when the last message is already the host's (use the normal last-message
  /// regen), when a user/System message breaks the guest tail, or outside a 1:1
  /// scene. The UI uses this to offer "regenerate the main character" on a host
  /// bubble that the last-message-only regen button can no longer reach.
  int? get regenerableHostBelowGuestsIndex {
    if (_activeGroup != null || _messages.isEmpty) return null;
    if (!_isGuestAuthoredMessage(_messages.last)) return null;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') return null;
      if (!_isGuestAuthoredMessage(m)) return i;
    }
    return null;
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


  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(int messageIndex, int direction) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    final oldIndex = msg.swipeIndex;

    // Guest-message swipes carry no Realism/Needs, so navigating between them
    // must never touch the active character's state (parity) — true even for a
    // guest who has since left the scene, hence the authoritative check.
    final isGuestMsg = _isGuestAuthoredMessage(msg);

    // Swiping left
    if (direction < 0) {
      if (newIndex >= 0) {
        msg.swipeIndex = newIndex;
        if (!isGuestMsg) _syncRealismStateForSwipe(msg, oldIndex, newIndex);
        await _saveChat();
        notifyListeners();
      }
      return;
    }

    // Swiping right
    if (newIndex < msg.swipes.length) {
      // Navigate to existing swipe
      msg.swipeIndex = newIndex;
      if (!isGuestMsg) _syncRealismStateForSwipe(msg, oldIndex, newIndex);
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
    if (_messages.isEmpty || _isGenerating || _guestBusy) return;

    // Only continue if the last message is from a bot (non-user, non-system)
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      await _generateResponse(GenerationMode.continue_);
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


  // ensureInterCharacterRelationshipsSeeded / updateInterCharacterFeelingsFromRecentExchange
  // moved verbatim to RelationshipService (with callbacks for group/messages). Old bodies deleted.


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
  /// Embed the recent message window for RAG memory (fire-and-forget).
  ///
  /// Normally keyed on the active character (or group bucket). Scene Guests
  /// Phase 4 passes [characterIdOverride] = the guest's id so the just-finished
  /// guest exchange is stored under the GUEST's own id — the same id the guest
  /// retrieves under in [_getMemorySourceIds] — giving guests episodic memory
  /// without touching the host's embeddings.
  void _maybeEmbedMessages({String? characterIdOverride}) {
    if (_memoryService == null || !_storageService.memorySettings.ragEnabled) {
      return;
    }
    if (_currentSessionId == null) return;
    if (_messages.length < _storageService.memorySettings.ragWindowSize) return;

    final characterId = characterIdOverride ?? _getCharacterId();

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


  // Two god-owned "since last" counters for the independent periodic features.
  // Facts/auto-persona uses the first (tied to autoPersonaInterval).
  // Character evolution uses its own (tied to evolutionInterval) so the UI slider
  // and setting actually control when evolution fires.
  // Both must be zeroed on *all* the same reset/new-chat/group/load paths as the
  // flags (see every "keep reset blocks in sync" + "incomplete zeroing... now complete"
  // + explicit sites below and in the evolution/fact wiring sections).
  int _userMessagesSinceLastPeriodicEval = 0; // facts / auto-persona cadence
  bool _isExtractingFacts =
      false; // secondary runtime flag (transient guard for fact extraction leaf); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths to prevent leak of in-flight state across contexts (see CLAUDE.md "keep reset blocks in sync" + "incomplete zeroing..." (leaves incl fact/evo/verif + needs_impact etc)). The facts counter must likewise be zeroed on those paths (prevents stale/early trigger after context switch). Character-evolution cadence is driven separately by _characterEvolutionCount vs evolutionInterval (no side-counter), so only this facts counter needs zeroing on those paths.

  /// Coordinator for the two independent periodic background evals (fact extraction + character evolution).
  /// Facts uses its dedicated counter.
  /// Evolution decides due using live user message count in the chat vs the persisted per-char evolution count.
  /// This makes the "Evolve every X messages" setting (slider) reliably control the schedule, even after
  /// loads, switches, or enabling mid-chat. (Replaces fragile side-counter for evolution cadence.)
  // Thin delegation / coord (per-feature cadence counts + per-feature guards + enabled/Interval checks
  // + call to sequence or direct thins here; full work in the step 13/14 leaves;
  // "thin delegation here; full fact extraction in step 13"; "thin delegation here; full character evolution in step 14").
  // 0 new god private _ methods (only edits to these two existing coordinators + thins).
  void _maybeRunPeriodicEvals() {
    // Scene Guest cast detection (1:1 only; independent of the facts/evolution
    // settings below). Runs on its own cadence and fires-and-forget so it never
    // blocks the turn. See _maybeRunCastDetection.
    _maybeRunCastDetection();

    final autoPersona = _storageService.memorySettings.autoPersonaEnabled;
    final autoEvolution =
        _storageService.memorySettings.characterEvolutionEnabled;
    if (!autoPersona && !autoEvolution) return;
    if (_llmProvider == null) return;

    // Note: this path is *not* gated on !_observerMode.
    // Character evolution is deliberately allowed in Director Mode (see
    // _triggerCharacterEvolution for rationale). Realism/Needs simulation is
    // the only system that pauses in Director Mode.

    // Per-feature advance + due checks. Use the *specific* busy flag so one feature
    // can make progress even if the other is currently running (independent schedules).
    bool factsDue = false;
    bool evoDue = false;

    if (autoPersona && !_isExtractingFacts) {
      _userMessagesSinceLastPeriodicEval++;
      if (_userMessagesSinceLastPeriodicEval >=
          _storageService.memorySettings.autoPersonaInterval) {
        _userMessagesSinceLastPeriodicEval = 0;
        factsDue = true;
      }
    }

    if (autoEvolution && !_isEvolvingCharacter) {
      // Cadence is "evolve every N turns vs the persisted evolution count" — robust
      // across loads/reloads (no fragile side-counter). In a GROUP this counts the
      // speaker's OWN turns + their OWN evolution count, so each character evolves
      // every N of THEIR turns. (Previously a group counted TOTAL user messages, so
      // a 2-character group evolved each character ~twice as fast, worse with more
      // characters — see the user report.) 1:1 counts user messages as before.
      final interval = _storageService.memorySettings.evolutionInterval;
      if (interval > 0) {
        if (_activeGroup != null && _activeCharacter != null) {
          final sid = _getCharacterIdFromCard(_activeCharacter!);
          final speakerTurns = _messages
              .where((m) => !m.isUser && m.characterId == sid)
              .length;
          final speakerEvos = _groupEvolutionCounts[sid] ?? 0;
          if (speakerTurns ~/ interval > speakerEvos) {
            evoDue = true;
          }
        } else {
          final userMsgCount = _messages.where((m) => m.isUser).length;
          if (userMsgCount ~/ interval > _characterEvolutionCount) {
            evoDue = true;
          }
        }
      }
    }

    if (!factsDue && !evoDue) return;

    if (factsDue && evoDue) {
      debugPrint(
        '[Periodic] ▶ Triggering periodic evals (facts every ${_storageService.memorySettings.autoPersonaInterval}, evolution every ${_storageService.memorySettings.evolutionInterval} user messages)',
      );
    } else if (factsDue) {
      debugPrint(
        '[Periodic] ▶ Triggering fact extraction (every ${_storageService.memorySettings.autoPersonaInterval} user messages)',
      );
    } else {
      debugPrint(
        '[Periodic] ▶ Triggering character evolution (every ${_storageService.memorySettings.evolutionInterval} user messages)',
      );
    }

    _runPeriodicEvalsInSequence(runFacts: factsDue, runEvolution: evoDue);
  }

  /// Cadence + trigger for Scene Guest cast detection (1:1 only). Advances the
  /// dedicated counter on each primary turn and, on the interval, runs the
  /// detector fire-and-forget. A non-null result is surfaced as a pending popup
  /// (Chance-Time-style flag + notifyListeners). Never offers while one is
  /// already pending. The detector itself filters out the host/user/existing
  /// guests/already-offered names. Does ZERO Realism/Needs work.
  void _maybeRunCastDetection() {
    if (!sceneDetectionEnabled) return;
    if (_activeGroup != null) return; // 1:1 only by design
    if (_activeCharacter == null) return;
    if (_pendingGuestDetection != null) return; // one offer at a time

    _userMessagesSinceLastCastScan++;
    if (_userMessagesSinceLastCastScan < _castScanInterval) return;
    _userMessagesSinceLastCastScan = 0;

    // Fire-and-forget: never block the turn on the eval.
    _performCastScan();
  }

  /// Force an immediate cast-detection scan, bypassing the per-turn cadence.
  /// Backs the manual `/scan` command, so a recurring side character can be
  /// surfaced on demand — including in an already-loaded chat whose cadence
  /// counter reset on load. Returns true when a candidate was found and the
  /// offer popup was raised. Resets the cadence counter so the automatic scan
  /// won't immediately re-fire on the next turn.
  Future<bool> runCastDetectionNow() async {
    if (_activeGroup != null || _activeCharacter == null) return false;
    if (_pendingGuestDetection != null) return false;
    _userMessagesSinceLastCastScan = 0;
    // Re-resolve first so any guest whose library card was deleted is pruned
    // from the scene list — otherwise the detector still treats them as "already
    // a scene guest" and silently rejects re-detecting them (the exact symptom
    // of deleting a guest's card then /scan-ning for them again).
    await _resolveSceneGuestCards();
    // A manual scan is an explicit "look again", so forget prior in-session
    // dismissals/offers — otherwise a character you ignored (or added then
    // deleted) can never be re-surfaced without starting a fresh chat. Names
    // still genuinely in the scene are excluded by the live scene-guest filter.
    _offeredOrIgnoredGuestNames.clear();
    final detected = await _performCastScan();
    return detected != null;
  }

  /// Run one detection pass and, on a fresh hit, raise the offer popup (set the
  /// pending flag + notify). Shared by the automatic per-turn path and the
  /// manual `/scan` command so there is exactly ONE detect→surface path.
  /// Returns the surfaced candidate, or null when nothing was found.
  Future<DetectedCharacter?> _performCastScan() async {
    final token = _currentSessionId; // the scan is slow; the chat may switch
    final detected = await _ensureCastDetector().detect();
    if (detected == null) return null;
    // Bail if the chat/character/session changed (or we were disposed) during
    // the eval — otherwise a character detected from chat A's narration would
    // pop as an offer inside chat B and get minted into B's scene.
    if (_sceneChanged(token) || _activeGroup != null) return null;
    if (_pendingGuestDetection != null) return null;
    // Mark as offered immediately so a later scan won't re-propose it even if
    // the user leaves the popup open.
    _offeredOrIgnoredGuestNames.add(detected.name.trim().toLowerCase());
    _pendingGuestDetection = detected;
    notifyListeners();
    return detected;
  }

  /// Run the due steps (facts then evolution when both due) to preserve sequencing
  /// on coincident turns while allowing independent cadences.
  // Thin delegation / coord (the if(enabled) + await + thin calls here;
  // full extract in fact leaf step 13; full trigger/extract/LLM/persist/layering in evolution leaf step 14).
  Future<void> _runPeriodicEvalsInSequence({
    bool runFacts = false,
    bool runEvolution = false,
  }) async {
    if (runFacts && _storageService.memorySettings.autoPersonaEnabled) {
      debugPrint('[Periodic] Step: Extracting user facts...');
      await _extractFactsInBackground();
    }
    if (runEvolution &&
        _storageService.memorySettings.characterEvolutionEnabled) {
      debugPrint('[Periodic] Step: Evolving character...');
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
  // Evolution cadence decision lives in _maybeRunPeriodicEvals and uses actual #user messages in _messages
  // vs the persisted _characterEvolutionCount (or per-char in group). This ensures the UI slider
  // reliably schedules evolution on the configured interval (no mutable side-counter).

  bool _isEvolvingCharacter =
      false; // secondary runtime flag (transient guard for evolution_service leaf); must be defensively zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete paths to prevent leak of in-flight state across contexts (see every "keep reset blocks in sync" + "incomplete zeroing... now complete (see CLAUDE.md)" + evolution_service (stateless or prompt-only; no reset calls needed) + fact_extraction (stateless or prompt-only; no reset calls needed)). The _evolutionStatus / _evolutionError must likewise be zeroed on those paths (prevents stale UI status/error bleed after context switch). Evolution cadence itself uses _characterEvolutionCount vs evolutionInterval (no side-counter to zero).
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
  // The facts cadence counter (_userMessagesSinceLastPeriodicEval) is zeroed at *exactly* these same sites so its schedule doesn't leak stale "due soon" state after context switch. Evolution cadence uses _characterEvolutionCount vs evolutionInterval (no side-counter). Cross-refs e.g. setActiveCharacter ~1572 (precedent; lines may shift post edits -- verified live at doc time).
  String _evolutionStatus = '';
  String _evolutionError = '';

  /// Cached evolved fields (loaded from DB on character load)
  final Map<String, String> _evolvedPersonalities = {};
  final Map<String, String> _evolvedScenarios = {};
  int _characterEvolutionCount = 0;

  /// Kept as an instance getter (not moved to the evolution part) because test
  /// fakes (`FakeChatService implements ChatService`) override it — extension
  /// getters are statically dispatched and cannot be overridden via `implements`.
  int get characterEvolutionCount => _characterEvolutionCount;

  /// Per-character evolution counts (for group mode).
  final Map<String, int> _groupEvolutionCounts = {};


  /// Get the list of character IDs to search for RAG memory retrieval.
  /// Reads the current character's `memorySources` from the DB and includes
  /// those characters' embedding IDs alongside the current character.
  /// Resolve the RAG source character ids for retrieval.
  ///
  /// Normally keyed on the active character (or the group bucket). When a
  /// [guest] is supplied (Scene Guests Phase 4), retrieval is keyed on the
  /// guest's OWN id instead — the same id the guest embeds under via
  /// [_maybeEmbedMessages] — plus that guest's cross-character memory sources.
  /// This keeps the guest's episodic memory isolated from the host's: the
  /// host's memories are never injected on a guest turn, and vice versa.
  Future<List<String>> _getMemorySourceIds({CharacterCard? guest}) async {
    final currentId = guest != null
        ? _getCharacterIdFromCard(guest)
        : _getCharacterId();
    final sourceIds = <String>[currentId]; // always include self

    // Look up cross-character sources from DB (for the guest, or the active char)
    final sourceCard = guest ?? _activeCharacter;
    if (sourceCard != null && sourceCard.dbId != null) {
      try {
        final dbChar = await _db.getCharacterById(sourceCard.dbId!);
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

  // The individual _get* thins for relationship/emotion/time/behavioral/nsfw are no longer used
  // for main prompt assembly — the new _realismStateInjection composer owns the full
  // grouped "Speaker Internal State" output (see realism_state_injection.dart).
  // The sub-builders themselves are still instantiated and passed to the composer.
  // Chance Time remains separate (it is not part of the per-turn realism state bundle).


  /// Loads the active objectives for the given character in the current session.
  /// Safe to call from group objective UIs — does not mutate global _activeObjectives.
  ///
  /// Kept in the class body (not an extension) because [FakeChatService]
  /// overrides it in golden tests — extension members are statically dispatched
  /// and cannot be overridden.
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
    // In a group the flag is PER-CHARACTER (each speaker's eval reloads it via
    // loadNsfwScalarsForSpeaker), so the chat-wide toggle must be written into
    // EVERY member's _groupRealism entry — otherwise members keep their stale
    // (off) per-char flag and arousal is never evaluated for them. (1:1 just uses
    // the scalar above; this loop is a no-op there.)
    if (_activeGroup != null) {
      for (final c in _groupCharacters) {
        final id = _getCharacterIdFromCard(c);
        (_groupRealism[id] ??= <String, dynamic>{})['nsfwCooldownEnabled'] =
            enabled;
      }
    }
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
    // Enabling mid-chat: the needs vector is only seeded at chat start (see
    // chat_entry/group_entry), so a toggle-on after a needs-off start leaves it
    // empty and the sidebar shows no scores. Seed it now from the active
    // character/group baselines, mirroring the chat-start init so 1:1 and group
    // behave identically.
    if (enabled && _needsSimulation.vector.isEmpty) {
      if (_activeGroup != null) {
        _needsSimulation.initializeFreshWithDefaults(const {
          'hunger': 80,
          'bladder': 80,
          'energy': 80,
          'social': 80,
          'fun': 80,
          'hygiene': 80,
          'comfort': 80,
        });
      } else {
        final ext = _activeCharacter?.frontPorchExtensions;
        if (ext != null) {
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
          _needsSimulation.initializeFresh();
        }
      }
    }
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
        newExt.ensureStableId();
        char.frontPorchExtensions = newExt;

        if (char.imagePath != null) {
          final file = File(char.imagePath!);
          if (await file.exists()) {
            await v2Service.saveCardAsPng(
              char,
              char.imagePath!,
              char.imagePath!,
            );
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

    final ext =
        _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();
    final newExt = ext.copyWith(
      needsDecayHunger: key == 'hunger' ? value : null,
      needsDecayBladder: key == 'bladder' ? value : null,
      needsDecayEnergy: key == 'energy' ? value : null,
      needsDecaySocial: key == 'social' ? value : null,
      needsDecayFun: key == 'fun' ? value : null,
      needsDecayHygiene: key == 'hygiene' ? value : null,
      needsDecayComfort: key == 'comfort' ? value : null,
    );
    newExt.ensureStableId();
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
    _guestStatusClearTimer?.cancel();
    _characterRepository?.removeListener(_onCharacterLibraryChanged);
    super.dispose();
  }
}
