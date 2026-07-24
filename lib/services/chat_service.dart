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
import 'dart:math' as math;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/vision_eval.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/chat_theme_overrides.dart';
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
import 'package:front_porch_ai/utils/group_realism_blobs.dart'; // parseGroupRealismSeeds — fresh-chat group realism reset (fixation-bleed fix)
import 'package:front_porch_ai/services/expression_classifier.dart'; // top-level for ExpressionClassifierService type in @Dep shim (pre-existing)
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';
import 'package:front_porch_ai/services/chat/image_command_service.dart';
import 'package:front_porch_ai/services/chat/cast_detector.dart';
import 'package:front_porch_ai/services/chat/scene_guest_director.dart';
import 'package:front_porch_ai/services/chat/scene_guest_factory.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/prompt_plan.dart';
import 'package:front_porch_ai/services/chat/stop_sequences.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/chat/needs_impact_evaluator.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/relationship_milestones.dart';
import 'package:front_porch_ai/services/chat/expression_classifier.dart'; // leaf for ExpressionService (post-extraction)
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/lorebook_collection.dart';
import 'package:front_porch_ai/services/chat/lorebook_injector.dart';
import 'package:front_porch_ai/services/chat/lorebook_scanner.dart';
import 'package:front_porch_ai/services/chat/lorebook_timed_effects.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/author_note_builder.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';
import 'package:front_porch_ai/services/chat/absence_tracker.dart';
import 'package:front_porch_ai/services/chat/afk_flavor.dart';
import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/services/chat/dream_service.dart';
import 'package:front_porch_ai/services/chat/promise_debt_service.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/services/chat/milestone_feed.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/chaos_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/needs_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/realism_state_injection.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/realism_evals.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';
import 'package:front_porch_ai/services/chat/objective_proposal.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/journal_maintenance.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/chat/journal_review.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/journal_injection.dart';
import 'package:front_porch_ai/services/chat/growth_ops.dart';
import 'package:front_porch_ai/services/chat/growth_physics.dart';
import 'package:front_porch_ai/services/chat/growth_review.dart';
import 'package:front_porch_ai/services/chat/growth_service.dart';
import 'package:front_porch_ai/services/chat/growth_store.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:drift/drift.dart' as drift;

// Cohesive method groups extracted into part files to keep this file shrinking
// toward the 500-line cap (see CLAUDE.md). Parts share this library's imports and
// private members; behaviour is unchanged.
part 'chat/chat_service_group_read.dart';
part 'chat/chat_service_group_settings.dart';
part 'chat/chat_service_growth.dart';
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
part 'chat/chat_service_images.dart';
part 'chat/chat_service_photo.dart';
part 'chat/chat_service_idle_autonomous.dart';
part 'chat/chat_service_greeting.dart';
part 'chat/chat_service_prompt_blocks.dart';
part 'chat/chat_service_scene_guest.dart';
part 'chat/chat_service_controls.dart';

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

  // Sidebar task-generation prefs, hoisted from ObjectivePanel widget state:
  // the panel's State is recreated on sidebar rebuilds (every realism turn),
  // which reset the NSFW toggle each message (field report). Session-held on
  // purpose — NOT persisted, so NSFW tasks default OFF on a fresh launch.
  bool objectiveNsfwTasks = false;
  int objectiveTaskCount = 5;

  /// Armed only while the TURN-path completion check runs (see
  /// _maybeCheckTaskCompletionSync try/finally): check-driven objective
  /// mutations record regen turn-ops only when armed, so the UI's manual
  /// "Check now" (forceCheckCompletion) never records — a regen must not
  /// undo a user-triggered check. Scoped by try/finally; no reset needed.
  bool _objectiveTurnOpsArmed = false;
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

  // ── Dynamic Responses (idle timer / fourth-wall auto-ping) ─────────────
  Timer? _idleTimer;
  String? _pendingIdleCue;
  bool _autoResponseInProgress = false;
  bool _hasCompletedExchange = false;
  int _consecutiveAutoResponses = 0;
  // The consecutive-response cap lives in the persisted
  // generationSettings.dynamicResponseMaxMessages (default 3) so the sidebar
  // flyout, /afk --messages, and the settings all share one source of truth.

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

  // Scene Guests grow Growth Rings exactly like members do — rings are keyed
  // by the guest's stable charId in the growth_rings table, so no per-guest
  // evolution state lives here anymore (the growth pass includes 1:1 guests
  // who spoke in the window via resolvePassOwners).

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

  /// True while forked-in character entrances are still playing. Exposed so the
  /// composer can mirror sendMessage's `_entrancesInFlight` early-return and
  /// avoid consuming (saving/clearing) an attached photo for a turn that
  /// sendMessage would silently drop. See _sendCurrentMessage.
  bool get entrancesInFlight => _entrancesInFlight;

  /// True from the start of a photo turn's captioning through the end of its
  /// send flow. Because the offline caption await (and the post-gen vision
  /// caption) run while `_isGenerating` is false, this is the guard that keeps
  /// a second sendMessage from interleaving during those windows — the UI and
  /// sendMessage entry both check it. Photo turns only; text turns are
  /// unaffected (they are covered by `_isGenerating`).
  bool get isPhotoTurnInFlight => _photoTurnInFlight;
  bool _photoTurnInFlight = false;

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
      _setGuestStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
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

    final additional = <CharacterCard>[if (!isPresentGuest) card, ...present];
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
      _setGuestStatus(
        '⚠ Group support is unavailable right now.',
        isError: true,
      );
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

  /// `/image` slash-command orchestrator (lazily built in
  /// chat_service_images.dart; callbacks read live state, so it survives
  /// chat switches like [_commandHandler] does).
  ImageCommandService? _imageCommand;

  /// Prompt-review pause for /image (Chance-Time-style pending flag +
  /// completer): when the review setting is on, the crafted prompt parks
  /// here until the UI (desktop dialog / web modal) resolves it via
  /// [resolveImagePromptReview] — see chat_service_images.dart.
  String? _pendingImagePromptReview;
  Completer<String?>? _imageReviewCompleter;

  /// Append an already-saved generated image to the conversation as a
  /// character message (empty text; the bubble renders the image from
  /// metadata). Shared by the /image slash command, the Image Studio's
  /// "Send to chat", and the web insert-image endpoint. Lives in the class
  /// (not the images extension) so web-facade fakes can override it.
  Future<void> addGeneratedImageMessage(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) async {
    if (_activeCharacter == null && _activeGroup == null) return;
    _messages.add(
      ChatMessage(
        text: '',
        sender: senderName ?? _activeCharacter?.name ?? 'Narrator',
        isUser: false,
        characterId: characterId,
        metadata: {
          'is_generated_image': true,
          'image_path': path,
          'image_prompt': prompt,
        },
      ),
    );
    await _saveChat();
    notifyListeners();
  }

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
      configureAfk: (enabled, maxMessages, intervalSeconds) {
        // Drive the same persisted Dynamic Responses settings the sidebar panel
        // uses (single source of truth — no parallel AFK state). Returns the
        // effective values so the handler can word its confirmation.
        final gen = _storageService.generationSettings;
        if (!enabled) {
          gen.setDynamicResponses(false);
          pauseDynamicResponses();
          return (
            enabled: false,
            maxMessages: gen.dynamicResponseMaxMessages,
            intervalSeconds: gen.dynamicResponseInterval,
          );
        }
        if (intervalSeconds != null) {
          gen.setDynamicResponseInterval(intervalSeconds);
        }
        if (maxMessages != null) gen.setDynamicResponseMaxMessages(maxMessages);
        gen.setDynamicResponses(true);
        // Fresh AFK run. resumeDynamicResponses arms now if an exchange already
        // happened this session; otherwise the timer arms after the next reply.
        _consecutiveAutoResponses = 0;
        resumeDynamicResponses();
        return (
          enabled: true,
          maxMessages: gen.dynamicResponseMaxMessages,
          intervalSeconds: gen.dynamicResponseInterval,
        );
      },
      generateImage: (args) => _ensureImageCommand().handle(args),
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

  /// Primary turns since the last cast-detection scan (zeroed at the same
  /// Scene Guest reset sites alongside `_pendingGuestDeparture = null`).
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
      // Shared tools transport (one probe per backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
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
      mint: (onStatus) => _mintSceneGuest(
        detected.name,
        detected.descriptor,
        onStatus: onStatus,
      ),
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
    final hostFirst = (_activeCharacter?.name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    final userFirst = _userPersonaService.persona.name
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
    if (firstLc == hostFirst || firstLc == userFirst) return '';
    final re = RegExp(
      r'\b' + RegExp.escape(first) + r'\b',
      caseSensitive: false,
    );
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
          if (_sceneChanged(token)) {
            return; // disposed or chat switched mid-pass
          }
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

  // ── Real-absence awareness (Living Time §2) ──
  // Computed in-memory at session load from the last saved message's
  // updatedAt; nothing is stored or transmitted (privacy-by-design contract
  // in absence_tracker.dart). Story clock untouched.
  Duration _absenceGap = Duration.zero;
  bool _absenceAckPending = false;
  bool _absenceAckConsumed = false;
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
    if (_activeGroup == null) return const [];
    // Post-group-filter truth (what actually injects), deduplicated by
    // content to avoid showing the exact same lore text twice.
    final seen = <String>{};
    return [
      for (final e in _lorebookInjector.activeEntries(
        sessionSeed: _currentSessionId ?? '',
      ))
        if (seen.add(e.content)) e,
    ];
  }

  // RAG settings for the active group (stored in the hidden checkpoint, no DB schema change)
  bool _groupRagEnabled = true;
  int _groupRetrievalCount = 4;
  double _groupMemoryBudgetPercent = 10.0;
  Map<String, double> _groupCharacterRAGPriorities = {};

  // Director Mode state is now owned by _groupManager when active.
  // The public getters below delegate to it.
  // ── Author's Note ──
  String _authorNote = '';
  int _authorNoteStrength = 4;

  // ── Per-chat avatar gallery ("looks") selection ──
  // {characterId: selectedLookAvatarId} for THIS session, decoded from the
  // session's selectedLookAvatarId column on load. A map (not one id) so a group
  // chat remembers a look per participant; 1:1 is just a one-entry map. Reset
  // per session in loadSession; empty when no session.
  Map<String, String> _selectedLooks = {};

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
  // The single event the web/mobile "reveal your fate" modal shows + accepts
  // while sendMessage is parked on the completer below. The desktop samples its
  // own spinning wheel; a phone has no room for one, so we pre-pick one event
  // from the same pool. Lives only during the park (set at the gate, cleared on
  // resume) — see [isAwaitingChanceTime] / [acceptPendingChanceTime].
  String? _webChanceTimeEvent;

  // ── Sims/Needs Simulation (extracted) + Needs Impact Evaluator ──
  // Straight decay ticks in _needsSimulation; model deltas (+ optional Director review when authority) in _needsImpactEvaluator.
  // See CLAUDE.md for full reset keep-sync + "incomplete zeroing now complete" + buffer removal + authority decision (simple model+Director path).
  bool _needsSimEnabled = false;
  bool _enjoysLowHygiene =
      false; // inversion for hygiene (enjoys being dirty/sweaty/musky)

  // Legacy shared group decay map. No longer the runtime source of truth (that
  // is each member's card ext, via `_activeDecayRates()`); retained only as a
  // load/save + fallback bridge for pre-per-member groups (see session state).
  Map<String, int> _groupDecayRates = {};

  // Forwarding for critical threshold (moved to NeedsSimulation after buffer removal; UI + cards still reference the old ChatService surface)
  static int get needCriticalThreshold => NeedsSimulation.needCriticalThreshold;

  // ── Passage of time (extracted to TimeService) ───────────────────────────
  // (Declared early among late finals for init safety because needs/others close over its getters via cbs.
  // Logically added "after the other late finals" per extraction sequence; 0 new god privates.)
  late final _timeService = TimeService(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    // Shared tools transport (one probe per backend identity, app-wide).
    fireToolEval: _fireToolEval,
    probe: _toolProbe,
    getBackendIdentity: () => _evalBackendIdentity,
    onSetPendingRealismMetadata: (key, value) {
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata![key] = value;
    },
    onPatchLastMessageRealismState: (tod, dc, clockIso) {
      if (_messages.isNotEmpty) {
        final lastMsg = _messages.last;
        lastMsg.activeMetadata ??= {};
        final existingState = lastMsg.activeMetadata!['realism_state'];
        if (existingState is Map<String, dynamic>) {
          existingState['timeOfDay'] = tod;
          existingState['dayCount'] = dc;
          existingState['storyClock'] = clockIso;
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
  // Keyword scan (set isTriggered + remaining=sticky), decrement (post-AI
  // pre-set only), and reset of non-const trigger state live in
  // _lorebookScanner (plain class). ChatService owns via late final + thin
  // delegations at *all* call sites.
  // The entry universe comes from ONE enumerator: _collectLoreRefs →
  // collectLoreEntryRefs (group book + group worlds + member/1:1 books +
  // attached worlds). Scanning always covers everything (inherit=true);
  // the group's inheritCharacterLorebooks flag only filters injection and
  // the sidebar (getActiveGroupLoreEntries), matching prior behavior.
  // 1:1 vs group parity: scanner processes whatever the enumerator yields.
  // Reset hygiene: resetLorebookTriggerState() called from every keep-sync
  // site (startNewChat 1:1+group/ext+non-ext, setActive*, _load empty/
  // 0-session, setActiveGroup defensive+post, etc).
  late final _lorebookScanner = LorebookScanner(
    onNotify: notifyListeners,
    getEntryRefs: () => _collectLoreRefs(inheritOverride: true),
    getRecentMessages: (count) {
      final includeNames = _storageService.lorebookSettings.includeNames;
      final start = _messages.length > count ? _messages.length - count : 0;
      return [
        for (final m in _messages.sublist(start))
          m.characterId == '__director__'
              ? '[Director: ${m.text}]'
              : (includeNames ? '${m.sender}: ${m.text}' : m.text),
      ];
    },
    getGlobalScanDepth: () => _storageService.lorebookSettings.scanDepth,
    getRecursiveScan: () => _storageService.lorebookSettings.recursiveScan,
    getMaxRecursionSteps: () =>
        _storageService.lorebookSettings.maxRecursionSteps,
    timedEffects: _loreTimedEffects,
    getChatLength: () => _messages.length,
    resolveKeyMacros: (key) {
      final ch =
          _activeCharacter ??
          (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
      if (ch == null) return key;
      return _macroResolver.resolve(
        key,
        _buildChatMacroContext(ch),
        section: 'lorekeys',
      );
    },
  );

  /// Per-chat lore session state (ST sticky/cooldown timers, macro locals,
  /// chat-scoped lorebook) — persisted inside the session's groupRealismState
  /// blob via additive keys, hydrated on session load, cleared at session
  /// boundaries via the scanner reset.
  final _loreTimedEffects = LorebookTimedEffects();

  /// The chat-scoped lorebook: lore that lives and dies with this one
  /// conversation. The sidebar edits it directly (live instance) and calls
  /// [commitChatLorebookEdit] to notify + persist.
  Lorebook get chatLorebook => _loreTimedEffects.chatLorebook;

  Future<void> commitChatLorebookEdit() async {
    notifyListeners();
    await _saveChat();
  }

  // Pure-read injection engine (positions, ordering, budget, inclusion
  // groups). Consumes the same enumerator as the scanner but honors the
  // group's inherit flag (injection semantics).
  late final _lorebookInjector = LorebookInjector(
    getEntryRefs: () => _collectLoreRefs(),
    getSettings: () => _storageService.lorebookSettings,
    isStickyActive: (e) =>
        _loreTimedEffects.isStickyActive(e, _messages.length),
  );

  /// Names of lore entries dropped by the token budget on the last
  /// generation, plus the meter numbers the sidebar shows.
  List<String> _lastLoreOverflow = const [];
  List<String> get lastLoreOverflow => _lastLoreOverflow;
  int _lastLoreTokens = 0;
  int _lastLoreBudget = 0;
  int get lastLoreTokens => _lastLoreTokens;
  int get lastLoreBudget => _lastLoreBudget;

  /// Read surface for the sidebar's sticky/cooldown countdown pills.
  LorebookTimedEffects get loreTimedEffects => _loreTimedEffects;

  /// Mutation-free "would trigger next" preview for the composer draft.
  Set<LorebookEntry> previewLoreTriggers(String draft) =>
      _lorebookScanner.previewTriggers(draft);

  /// The post-group-filter active lore set — what is ACTUALLY injected this
  /// turn. Sidebar dots and the web facade read this so they never show an
  /// inclusion-group loser as active.
  Set<LorebookEntry> currentlyActiveLoreEntries() => _lorebookInjector
      .activeEntries(sessionSeed: _currentSessionId ?? '')
      .toSet();

  // The group lorebook is stored as a JSON string on the group row. Parse it
  // ONCE and keep the live instance — the scanner writes trigger state onto
  // these entry objects, so a fresh parse per read (the pre-Phase-2 behavior)
  // silently discarded every keyword trigger and left group books constant-only.
  // String-compare invalidation: editing the book in group settings replaces
  // the JSON string, which re-parses (and intentionally clears trigger state,
  // same as editing semantics elsewhere).
  Lorebook? _cachedGroupBook;
  String? _cachedGroupBookJson;
  Lorebook? get _activeGroupLorebook {
    final raw = _activeGroup?.groupLorebook ?? '';
    if (raw.isEmpty) {
      _cachedGroupBook = null;
      _cachedGroupBookJson = null;
      return null;
    }
    if (_cachedGroupBookJson != raw) {
      try {
        _cachedGroupBook = Lorebook.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _cachedGroupBook = Lorebook(entries: []);
      }
      _cachedGroupBookJson = raw;
    }
    return _cachedGroupBook;
  }

  /// The ONE lore-entry enumerator (replaces the five duplicated collection
  /// loops in generation/impersonate/sidebar/pre-AI-snapshot/scanner).
  /// [inheritOverride] forces member books in for scanning/reset; injection
  /// and sidebar pass null to honor the group's inherit flag.
  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) {
    return collectLoreEntryRefs(
      characters: _activeGroup != null
          ? _groupCharacters
          : (_activeCharacter != null
                ? [_activeCharacter!]
                : const <CharacterCard>[]),
      chatLorebook: _loreTimedEffects.chatLorebook,
      groupLorebook: _activeGroupLorebook,
      groupWorldNames: _activeGroup?.worldIds ?? const [],
      resolveWorld: (name) =>
          _worldRepository.worlds.where((w) => w.name == name).firstOrNull,
      inherit:
          inheritOverride ?? (_activeGroup?.inheritCharacterLorebooks ?? true),
    );
  }

  /// Central macro resolver for prompt template expansion.
  late final _macroResolver = MacroResolver();

  /// In-memory clock for {{idle_duration}} — set on each user send; null
  /// after a restart (the macro passes through untouched then).
  DateTime? _lastUserMessageAt;

  /// Full chat-context MacroContext for prompt builds: card fields, group
  /// roster, last messages, idle clock, and the macro variable stores
  /// (locals ride _loreTimedEffects per chat; globals live in settings).
  /// Shared by generation, impersonation, and lore-key resolution.
  MacroContext _buildChatMacroContext(
    CharacterCard speaking, {
    String? scenario,
  }) {
    ChatMessage? lastUser;
    ChatMessage? lastChar;
    for (final m in _messages.reversed) {
      if (m.characterId == '__director__') continue;
      lastUser ??= m.isUser ? m : null;
      lastChar ??= !m.isUser ? m : null;
      if (lastUser != null && lastChar != null) break;
    }
    return MacroContext(
      userName: _userPersonaService.persona.name,
      characterName: speaking.name,
      chatId: _currentSessionId,
      characterId: speaking.dbId,
      description: speaking.description,
      personality: _getEffectivePersonality(speaking),
      scenario: scenario ?? speaking.scenario,
      userPersona: _userPersonaService.persona.persona,
      groupMemberNames: _activeGroup != null
          ? [for (final c in _groupCharacters) c.name]
          : null,
      lastMessage: _messages.isNotEmpty ? _messages.last.displayText : null,
      lastUserMessage: lastUser?.displayText,
      lastCharMessage: lastChar?.displayText,
      idleDuration: _lastUserMessageAt == null
          ? null
          : DateTime.now().difference(_lastUserMessageAt!),
      getLocalVar: (n) => _loreTimedEffects.localMacroVars[n],
      setLocalVar: (n, v) => _loreTimedEffects.localMacroVars[n] = v,
      getGlobalVar: _storageService.lorebookSettings.getGlobalMacroVar,
      setGlobalVar: _storageService.lorebookSettings.setGlobalMacroVar,
    );
  }

  /// Regex matching any `{{macro}}` or `{{macro::args}}` pattern.
  /// Used to detect stray unresolved macros in chat history.
  static final _macroPattern = RegExp(r'\{\{(\w+)(?:::(.+?))?\}\}');

  late final _needsSimulation = NeedsSimulation(
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getTimeOfDay: () => _timeService.timeOfDay,
    getRealismEnabled: () => _realismEnabled,
    getObserverMode: () => _observerMode,
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getGroupNeeds: _getGroupNeeds,
    setGroupNeeds: _setGroupNeeds,
    getEnjoysLowHygiene: () => enjoysLowHygiene,
    getNeedsSimEnabled: () => _needsSimEnabled,
    getCustomDecayRates: () => _activeDecayRates(),
    getWeather: () => currentWeather,
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
    getGroupCounter: (charId, key, {int defaultValue = 0}) =>
        (_groupRealism[charId]?[key] as num?)?.toInt() ?? defaultValue,
    setGroupCounter: (charId, key, v) => _setGroupRealismValue(charId, key, v),
    // Living Time §7 v1.5: bond/trust tier crossings → "Our Story" cards.
    // Fire-and-forget; plant never throws into the eval path. Diary owner is
    // the current speaker (1:1 host or group speaker whose scalars just moved).
    onTierCrossing: (crossing) {
      final sessionId = _currentSessionId;
      if (sessionId == null) return;
      final charId = _getCurrentSpeakerIdForRealism();
      if (charId.isEmpty) return;
      unawaited(
        RelationshipMilestones.plant(
          store: _journalStore,
          sessionId: sessionId,
          characterId: charId,
          crossing: crossing,
          sourcePositions: _messages.isEmpty
              ? const <int>[]
              : <int>[_messages.length - 1],
          storyDay: _timeService.dayCount,
          storyClock: _timeService.storyClockIso,
          maxCards: _storageService.memorySettings.journalMaxCards,
        ),
      );
    },
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
    // Shared tools transport (one probe per backend identity, app-wide).
    fireToolEval: _fireToolEval,
    probe: _toolProbe,
    getBackendIdentity: () => _evalBackendIdentity,
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
      // Transient banner only — never a persisted chat message. (The old
      // 'Interruption' line rode chat history, prompts, RAG, and journal
      // windows forever; same fix as cancelRealismEval.) This fires during
      // post-generation ONNX avatar classification, so the reply already
      // exists — consuming the flag here is correct (nothing to abort).
      _setGuestStatus('Realism classification interrupted.');
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
    getShouldTrackInterCharacterRelationships: () =>
        _shouldTrackInterCharacterRelationships,
    getGroupInt: _getGroupInt,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getInterCharacterRelationships:
        _relationshipService.getInterCharacterRelationships,
  );

  late final _emotionInjection = EmotionInjection(
    getRealismEnabled: () => _realismEnabled,
    getCharacterEmotion: () => _characterEmotion,
    getEmotionIntensity: () => _emotionIntensity,
  );

  late final _behavioralInjection = BehavioralInjection(
    relationshipService: _relationshipService,
    getRealismEnabled: () => _realismEnabled,
  );

  late final _timeInjection = TimeInjection(
    timeService: _timeService,
    // One-shot, opt-in (default OFF), coarse-worded, speculation-forbidding —
    // living-time-features.md §2 "Privacy by design".
    getAbsenceNote: () {
      if (!_storageService.absenceAckEnabled || !_absenceAckPending) {
        return null;
      }
      final phrase = absencePhrase;
      return phrase == null ? null : AbsenceTracker.ackNote(phrase);
    },
  );

  /// Coarse absence bucket ("a few days"), or null under the threshold /
  /// fresh chat. Words only — never digits (see AbsenceTracker).
  String? get absencePhrase => AbsenceTracker.bucketPhrase(
    _absenceGap,
    thresholdHours: _storageService.absenceThresholdHours,
  );

  /// [absencePhrase] gated by the welcome-back-banner setting — the ONE gate
  /// both the desktop banner and the web facade read, so they can't drift.
  String? get absenceBannerPhrase =>
      _storageService.absenceBannerEnabled ? absencePhrase : null;

  /// Today's story weather, or null when off (living-time-features.md §3).
  /// Pure recompute from existing state — nothing stored, so save/load and
  /// group re-entry agree for free. Gate: realism + passage-of-time + the
  /// global toggle. Consumed by the injection leaf, the needs decay
  /// modifiers, the sidebar TimeStrip, and the web facade — one source.
  DailyWeather? get currentWeather {
    if (!_realismEnabled ||
        !_timeService.passageOfTimeEnabled ||
        !_storageService.weatherEnabled) {
      return null;
    }
    final seed = _currentSessionId;
    if (seed == null) return null;
    return WeatherEngine.weatherFor(
      sessionSeed: seed,
      dayCount: _timeService.dayCount,
      date: _timeService.clock,
    );
  }

  late final _weatherInjection = WeatherInjection(
    getWeather: () => currentWeather,
  );

  // ── Ambitions (Living Time §6) ──
  late final _ambitionService = AmbitionService(
    journalStore: _journalStore,
    growthStore: _growthStore,
    fireEval: (prompt) async {
      final raw = await _llmEvalEngine.fireLLMEval(prompt);
      return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
    },
    getMaxCards: () => _storageService.memorySettings.journalMaxCards,
    onWaypoint: () {
      _journalMaintenance.eventKickPending = true;
      _growthService.eventKickPending = true;
    },
    onCacheWarmed: () {
      if (!_disposed) notifyListeners();
    },
  );

  /// Sidebar/web read surface (Living Time §6): [card]'s ambitions with
  /// live progress — triggers the lazy cache warm, so first render may show
  /// "just beginning" and correct itself one notify later. The ONE merge of
  /// card-authored definitions + per-chat progress; desktop and web both
  /// read through it so they can't drift.
  List<({String text, int progress})> ambitionsFor(CharacterCard card) {
    final sessionId = _currentSessionId;
    final list = card.frontPorchExtensions?.ambitions ?? const [];
    if (sessionId == null || list.isEmpty) return const [];
    final cid = _getCharacterIdFromCard(card);
    _ambitionService.ensureCacheWarm(sessionId, cid);
    final progress =
        _ambitionService.cachedProgress(sessionId, cid) ?? const {};
    return [for (final a in list) (text: a, progress: progress[a] ?? 0)];
  }

  late final _ambitionInjection = AmbitionInjection(
    ambitionService: _ambitionService,
    getSessionId: () => _currentSessionId,
    getActiveCharacter: () => _activeCharacter,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getCharacterIdFromCard: _getCharacterIdFromCard,
  );

  // ── Promise & debt ledger (Train B) ──
  late final _promiseDebtService = PromiseDebtService(
    journalStore: _journalStore,
    fireEval: (prompt) async {
      final raw = await _llmEvalEngine.fireLLMEval(prompt);
      return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
    },
    getMaxCards: () => _storageService.memorySettings.journalMaxCards,
    applyTrustDelta: (d) => _relationshipService.applyTrustDelta(d),
    applyBondDelta: (d) => _relationshipService.applyScoreDelta(d),
    onSalienceKick: () {
      _journalMaintenance.eventKickPending = true;
      _growthService.eventKickPending = true;
    },
    onCacheWarmed: () {
      if (!_disposed) notifyListeners();
    },
  );

  late final _promiseDebtInjection = PromiseDebtInjection(
    promiseDebtService: _promiseDebtService,
    getSessionId: () => _currentSessionId,
    getActiveCharacter: () => _activeCharacter,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getUserName: () => _userPersonaService.persona.name,
  );

  // ── Dreams (Living Time §1) ──
  late final _dreamService = DreamService(
    fireEval: (prompt) async {
      final raw = await _llmEvalEngine.fireLLMEval(prompt);
      return raw == null ? null : _llmEvalEngine.stripThinkBlocks(raw);
    },
    isEnabled: () =>
        _realismEnabled &&
        _timeService.passageOfTimeEnabled &&
        _storageService.journalEnabled &&
        _storageService.dreamsEnabled,
  );

  late final _nsfwInjection = NsfwInjection(
    nsfwService: _nsfwService,
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
    getNeedsSimEnabled: () => _needsSimEnabled,
    getRealismEnabled: () => _realismEnabled,
    getIsGroupNonObserverMode: () => (_activeGroup != null && !_observerMode),
    getCurrentSpeakerIdForRealism: _getCurrentSpeakerIdForRealism,
    getGroupCharacters: () => _groupCharacters,
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
    weatherInjection: _weatherInjection,
    ambitionInjection: _ambitionInjection,
    promiseDebtInjection: _promiseDebtInjection,
    behavioralInjection: _behavioralInjection,
    nsfwInjection: _nsfwInjection,
    needsInjection: _needsInjection,
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
  // no reset calls needed; incomplete zeroing... now complete (see CLAUDE.md)) + realism_evals (stateless or prompt-only; no reset calls needed) + objective_proposal (stateless or prompt-only; no reset calls needed) + journal_maintenance (stateless or prompt-only; no reset calls needed) + cross-refs (e.g. setActiveCharacter:1572). Both startNew branches explicit.
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
    // Shared tools transport for the needs-impact eval (one probe per
    // backend identity, app-wide).
    fireToolEval: _fireToolEval,
    probe: _toolProbe,
    getBackendIdentity: () => _evalBackendIdentity,
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
    // Tools transport (realism_tools.dart): same door + probe memory the
    // Journal and Growth passes use, so a backend answers the "can you speak
    // tools?" question at most once per run across all three systems.
    fireToolEval: _fireToolEval,
    probe: _toolProbe,
    getBackendIdentity: () => _evalBackendIdentity,
    isEvalCancelled: () => _isCancellingRealismEval || _realismEvalCancelled,
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
    // Judge dossier: same identity the generation sees (personality +
    // description + growth-ring lines when enabled), budget-capped in the
    // builder. Under group impersonation `card` is the current speaker, so
    // per-speaker parity holds without extra dispatch here.
    getCharacterDossier: (card) => RealismPromptBuilder.characterDossier(
      name: card.name,
      personality: card.personality,
      description: card.description,
      growth: _growthService.growthLinesFor(card),
    ),
    getPrimaryObjective: () => primaryObjective,
    getActiveObjectives: () => _activeObjectives,
    setObjective: (text, {isPrimary = false, autoGenerateTasks = false}) =>
        setObjective(
          text,
          isPrimary: isPrimary,
          autoGenerateTasks: autoGenerateTasks,
          // Eval-proposed objectives belong to the turn being generated —
          // record them so regen can roll them back (turn-ops; the UI's
          // direct setObjective calls stay unrecorded).
          recordTurnOps: true,
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
      // Only the completion check retires through this cb (the UI's
      // clearObjective has its own db call) — record the turn-op so regen
      // can reactivate a quest the invalidated turn retired. Armed-gated:
      // manual "Check now" retirements are user actions, not turn ops.
      if (_objectiveTurnOpsArmed) {
        _recordObjectiveTurnOp({'op': 'deactivated', 'id': id});
      }
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
    // The completion check runs pre-generation; the flags are consumed by
    // _maybeRunJournalPass/_maybeRunGrowthPass post-generation (a finished
    // quest is a story beat worth journaling AND a moment characters grow).
    onObjectiveCompleted: () {
      _journalMaintenance.eventKickPending = true;
      _growthService.eventKickPending = true;
    },
    // Ambitions (Living Time §6): a whole quest finishing is the ONE moment
    // ambition progress can move. Fire-and-forget; owner resolved from the
    // objective row's characterId (per-character in groups by construction).
    onQuestAchieved: (obj) {
      final sessionId = _currentSessionId;
      if (sessionId == null) return;
      final card =
          _groupCharacters
              .where((c) => _getCharacterIdFromCard(c) == obj.characterId)
              .firstOrNull ??
          (_activeCharacter != null &&
                  _getCharacterIdFromCard(_activeCharacter!) ==
                      obj.characterId
              ? _activeCharacter
              : null);
      final ambitions = card?.frontPorchExtensions?.ambitions ?? const [];
      if (card == null || ambitions.isEmpty) return;
      unawaited(
        _ambitionService.onQuestAchieved(
          sessionId: sessionId,
          characterId: obj.characterId,
          characterName: card.name,
          objectiveText: obj.objective,
          ambitions: ambitions,
          storyDay: _timeService.dayCount,
          storyClock: _timeService.storyClockIso,
        ),
      );
    },
  );

  // ── The Journal (docs/design/journal-memory.md) ──
  // Per-chat, per-character memory cards + "Where we are" recap. One periodic
  // maintenance pass (journal_maintenance leaf) replaces the old summary +
  // fact-extraction jobs; the recap reuses the _summary/_summaryLastIndex/
  // _isSummaryGenerating scalars (and their persistence + reset hygiene) so
  // no new god state is introduced. Cards live in the journal_memories table
  // via journal_store; the injection builder renders the speaker's pinned +
  // hot cards into the prompt. Strictly session-scoped — no memory ever
  // crosses chats. 1:1 ↔ group parity by construction (same owner loop).
  late final _journalStore = JournalStore(
    getDb: () => _db,
    // Availability-guarded single-text embedder; null when RAG is off or the
    // sidecar is down, which just disables cold-card recall (no-RAG floor).
    embedText: (text) async => await _memoryService?.embedText(text),
  );

  // Review-first parking + the ONE proposal applier (both modes go through
  // it). Public via [journalReview] for the sidebar banner + review dialog.
  late final _journalReview = JournalReview(
    store: _journalStore,
    getSessionId: () => _currentSessionId,
    setRecap: (t) => _summary = t,
    setCursor: (i) => _summaryLastIndex = i,
    onSaveChat: _saveChat,
    onNotify: notifyListeners,
    getMaxCards: () => _storageService.memorySettings.journalMaxCards,
  );

  JournalReview get journalReview => _journalReview;

  /// Tools-vs-XML probe memory shared by the Journal and Growth passes —
  /// one probe per backend identity per run no matter which pass asks first.
  final _toolProbe = ToolTransportProbe();

  /// Tool-calling door shared by both background passes: same eval posture
  /// as _fireLLMEval (low temp, reasoning off). All backends probe — local
  /// KoboldCpp included (Qwen3 etc. call tools fine); incapable models fall
  /// back to the XML floor.
  Future<LlmToolResponse?> _fireToolEval(
    String prompt,
    List<Map<String, dynamic>> tools,
  ) async {
    final service =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    try {
      return await service.generateWithTools(
      GenerationParams(
        prompt: prompt,
        maxLength: 4000,
        temperature: 0.1,
        repeatPenalty: 1.15,
        topP: 0.5,
        xtcProbability: 0.0,
        reasoningEnabled: false,
        // Explicit thinking-off: Nano-GPT/OpenRouter only receive the
        // disable signal when the reasoning block is present, and it is
        // only emitted when a reasoning field is set. Without this a
        // ":thinking" model (e.g. Kimi K2.6) keeps reasoning during the
        // journal tool call, which returns tool calls only intermittently
        // (the "had to regen twice" symptom). 0 → {enabled:false,
        // max_tokens:0, exclude:true}, the strongest disable signal.
        reasoningMaxTokens: 0,
        stopSequences: const [],
      ),
      tools,
        // Whole-call deadline: a backend that accepts the request and never
        // answers (cold model reload after an idle unload, dead server queue,
        // or the call queued behind a long generation like character
        // creation) must not park a journal/realism pass forever. The timeout
        // THROWS — isToolTransportFailure classifies it so verdict sites fall
        // back to text for the round without branding the backend XML-only.
      ).timeout(kEvalToolCallTimeout);
    } on TimeoutException {
      // The deadline abandoned an in-flight call. On the single-slot local
      // backend that orphan holds the shared idle slot (_pendingRequest), so
      // waitForIdle callers — text evals, the Scene Guest mint — would hang
      // behind it indefinitely; tear it down. (If the server is hung on the
      // orphan, the server-side abort also frees anything queued behind it.)
      // Remote backends don't serialize on the slot — nothing to release.
      if (service is KoboldService) service.abortGeneration();
      rethrow;
    }
  }

  /// Backend+model identity key for the tools probe. Remote model name AND
  /// local model path both ride the key, so switching either re-probes tool
  /// support (capability is per model).
  String get _evalBackendIdentity {
    final service =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;
    return '${service.backendName}|${_storageService.remoteModelName}'
        '|${_storageService.lastUsedModelPath ?? ''}';
  }

  /// Active tool-support prober behind the sidebar's tool-calling pill:
  /// verdicts land on the same [_toolProbe] the passes use, auto-retests on
  /// backend/model switches, and backs the pill's tap-to-retest.
  late final _toolSupportTester = ToolSupportTester(
    probe: _toolProbe,
    fireToolEval: _fireToolEval,
    getBackendIdentity: () => _evalBackendIdentity,
    isBackendReady: () =>
        (testLlmServiceOverride ??
                _llmProvider?.activeService ??
                _koboldService)
            .isReady,
    isBusy: () => _isGenerating,
    onNotify: notifyListeners,
    // OpenRouter/Nano-GPT list tool support in their /models metadata, so the
    // auto-test seeds the probe for free instead of pinging the model. Gated
    // to the openRouter backend: oMLX runs at localhost (no metadata) and the
    // resolver returns null for any non-metadata host anyway — those, like
    // local backends, keep the runtime ping.
    fetchMetadataToolVerdict: () async {
      if (_llmProvider?.activeBackend != BackendType.openRouter) return null;
      final caps = await VisionSupportResolver.instance.capabilitiesForRemote(
        apiUrl: _storageService.remoteApiUrl,
        apiKey: _storageService.remoteApiKey,
        modelName: _storageService.remoteModelName,
      );
      return caps?.toolCalling;
    },
  );

  /// The current model's tool-calling verdict (sidebar pill + web facade).
  ToolCallSupport get toolCallSupport => _toolSupportTester.current;
  bool get isTestingToolSupport => _toolSupportTester.isTesting;

  /// Re-probe the current backend+model's tool support (pill tap).
  Future<void> testToolCalling() => _toolSupportTester.test(force: true);

  late final _journalMaintenance = JournalMaintenance(
    store: _journalStore,
    review: _journalReview,
    probe: _toolProbe,
    fireLLMEval: (p) => _fireLLMEval(p),
    fireToolEval: _fireToolEval,
    getReviewFirst: () => _storageService.memorySettings.journalReviewFirst,
    getBackendIdentity: () => _evalBackendIdentity,
    stripThinkBlocks: _stripThinkBlocks,
    getSessionId: () => _currentSessionId,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getGroupCharacters: () => _groupCharacters,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getMessages: () => _messages,
    getUserName: () => _userPersonaService.persona.name,
    getCursor: () => _summaryLastIndex,
    setCursor: (i) => _summaryLastIndex = i,
    getRecap: () => _summary,
    setRecap: (t) => _summary = t,
    getIsPassRunning: () => _isSummaryGenerating,
    setIsPassRunning: (v) => _isSummaryGenerating = v,
    getMaxCards: () => _storageService.memorySettings.journalMaxCards,
    onNotify: notifyListeners,
    onSaveChat: _saveChat,
    getCurrentStoryDay: () => _timeService.dayCount,
    getCurrentStoryClockIso: () => _timeService.storyClockIso,
  );

  /// Public door for the Journal UI (phase 3): the sidebar panel and the
  /// diary dialog read/mutate cards directly on the store (scoped by
  /// [currentSessionId] + the participant's stable id); the injection builder
  /// re-reads the DB every turn, so UI edits reach the prompt with no extra
  /// plumbing. Instance getter (not extension) so FakeChatService can
  /// override it via `implements` (see isGrowthPassRunning precedent).
  JournalStore get journalStore => _journalStore;

  /// "Our Story" timeline read-model (Living Time §7) — pure aggregation
  /// over data already persisted; the journal dialog's timeline tab and the
  /// web facade both read through this one instance.
  late final MilestoneFeed milestoneFeed = MilestoneFeed(getDb: () => _db);

  late final _journalInjection = JournalInjection(
    store: _journalStore,
    getSessionId: () => _currentSessionId,
    // Two-tier memory: receipts → live verbatim lines (positions are the
    // stable indices cards already store).
    getMessageAt: (p) =>
        p >= 0 && p < _messages.length ? _messages[p] : null,
    // Same scalar EmotionInjection reads — in group non-obs the pre-gen
    // load-into-scalars dance has set it to the upcoming speaker's emotion
    // by assembly time, so mood-congruent recall is per-speaker (parity).
    getCurrentEmotion: () => _realismEnabled ? _characterEmotion : '',
    getCurrentStoryDay: () => _timeService.dayCount,
    getStoryStartDate: () => _timeService.startDate,
  );

  // ── Growth Rings (docs/design/growth-rings.md) ──
  // Per-chat, per-character growth entries — replaced EvolutionService's
  // whole-personality rewrites (the evolved* session columns are dormant;
  // their content is distilled into rings by the first growth pass). Rings
  // live in the growth_rings table via growth_store, which also keeps the
  // sync injection cache (_getEffectivePersonality runs inside synchronous
  // prompt assembly). The pass is its own small background job with its own
  // cursor (growth_state) — deliberately NOT a rider on the Journal pass,
  // whose per-pass cooling is tuned to journalInterval. Scenario evolution
  // is retired: the recap owns "where we are" (_getEffectiveScenario below).
  // Trigger/cache/UI surface live in chat_service_growth.dart (part file).
  late final _growthStore = GrowthStore(
    getDb: () => _db,
    // Ring text is stored with real names, never {{char}}/{{user}} macros
    // (the timeline displays it verbatim on both surfaces). {{char}} maps to
    // the ring OWNER's name — active char, group member, or scene guest by
    // stable id; unknown owners (departed cast) keep the macro rather than
    // guessing, and {{user}} always resolves to the persona.
    resolveMacros: (charId, text) {
      String? name;
      if (_activeCharacter != null &&
          _getCharacterIdFromCard(_activeCharacter!) == charId) {
        name = _activeCharacter!.name;
      }
      if (name == null) {
        for (final c in _groupCharacters) {
          if (_getCharacterIdFromCard(c) == charId) {
            name = c.name;
            break;
          }
        }
      }
      if (name == null) {
        for (final g in _sceneGuestCards) {
          if (_getCharacterIdFromCard(g) == charId) {
            name = g.name;
            break;
          }
        }
      }
      return resolveGrowthMacros(
        text,
        charName: name,
        userName: _userPersonaService.persona.name,
      );
    },
  );

  late final _growthReview = GrowthReview(
    store: _growthStore,
    getSessionId: () => _currentSessionId,
    getIsGroup: () => _activeGroup != null,
    onApplied: () => _refreshGrowthCache(),
    onNotify: notifyListeners,
  );

  late final _growthService = GrowthService(
    store: _growthStore,
    review: _growthReview,
    probe: _toolProbe,
    fireLLMEval: (p) => _fireLLMEval(p),
    fireToolEval: _fireToolEval,
    stripThinkBlocks: _stripThinkBlocks,
    getBackendIdentity: () => _evalBackendIdentity,
    getSessionId: () => _currentSessionId,
    getActiveCharacter: () => _activeCharacter,
    getActiveGroup: () => _activeGroup,
    getGroupCharacters: () => _groupCharacters,
    getSceneGuestCards: () => _sceneGuestCards,
    getCharacterIdFromCard: _getCharacterIdFromCard,
    getMessages: () => _messages,
    getUserName: () => _userPersonaService.persona.name,
    getRecap: () => _summary,
    getJournalCards: (sessionId, charId) =>
        _journalStore.cardsFor(sessionId, charId),
    getGrowthEnabled: () =>
        _storageService.memorySettings.characterEvolutionEnabled,
    getReviewFirst: () => _storageService.memorySettings.growthReviewFirst,
    getIsPassRunning: () => _isGrowthPassRunning,
    setIsPassRunning: (v) => _isGrowthPassRunning = v,
    refreshCache: () => _refreshGrowthCache(),
    onNotify: notifyListeners,
  );

  // Effective getters (all injection paths route through these).
  String _getEffectivePersonality(CharacterCard card) =>
      _growthService.effectivePersonality(card);
  // Scenario evolution is retired (growth-rings design §3.2): the Journal
  // recap owns "where we are", so every mode uses the card's own scenario.
  String _getEffectiveScenario(CharacterCard card) => card.scenario;

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

  // ── Per-chat theme ──
  ChatThemeOverrides _sessionThemeOverrides = ChatThemeOverrides();

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

  /// The per-chat gallery look selected for [characterId] in the active session,
  /// or null (no look chosen → the character's library face shows). Keyed by the
  /// character's library id so the same character shares one selection across a
  /// group cast.
  String? selectedLookFor(String characterId) => _selectedLooks[characterId];

  /// Set (or clear, when [lookId] is null) the per-chat gallery look for
  /// [characterId] in the active session, persist the whole map to the session's
  /// selected-look column, and repaint. Never touches `imagePath` — the library
  /// face is independent of which look shows in a given chat.
  Future<void> setLookForCharacter(String characterId, String? lookId) async {
    final sid = _currentSessionId;
    if (sid == null || characterId.isEmpty) return; // never key by a blank id
    // decodeSelectedLooks also drops empty keys, so a blank would silently fail
    // to round-trip; refuse it here so the caller notices instead.
    if (lookId == null) {
      _selectedLooks.remove(characterId);
    } else {
      _selectedLooks[characterId] = lookId;
    }
    notifyListeners();
    await _db.setSelectedLookForSession(
      sid,
      encodeSelectedLooks(_selectedLooks),
    );
  }

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

  /// The active backend's live generation progress (truthful status bar):
  /// Kobold console counts, oMLX admin-stats poll, or LM Studio's runtime
  /// log — null for plain remote APIs, which expose no prefill data. Thin
  /// delegation; source selection lives in LLMProvider.activeLiveProgress.
  LiveGenProgress? get activeLiveProgress =>
      _llmProvider?.activeLiveProgress ?? _koboldService.liveProgress;

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
  ) {
    // Probe verdicts land from background passes and the manual test alike —
    // rebroadcast so the sidebar's tool-calling pill repaints live.
    _toolProbe.addListener(notifyListeners);
    // Local model path / remote model name changes alter the eval identity —
    // retest tool support for the new model (sidebar pill contract).
    _storageService.addListener(_onBackendIdentityMaybeChanged);
  }

  void _onBackendIdentityMaybeChanged() {
    if (_disposed) return;
    _toolSupportTester.onBackendMaybeChanged();
  }

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

  /// Per-chat theme overrides (preset + customized colors/font/background/border).
  ChatThemeOverrides get sessionThemeOverrides => _sessionThemeOverrides;
  set sessionThemeOverrides(ChatThemeOverrides value) {
    _sessionThemeOverrides = value;
    // Persist only when a chat is actually open. The web facade already guards
    // this, but a bare `_currentSessionId!` would crash any other caller that
    // sets the theme with no active session (session close mid-save, tests).
    final sid = _currentSessionId;
    if (sid != null) {
      _db.setThemeOverrides(sid, value.toJsonString());
    }
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
      _realismEnabled &&
      !_autoResponseInProgress &&
      (_activeGroup == null || !_observerMode);

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
    // Group chats have no single "active character" hygiene preference — it is
    // strictly per-speaker (the injection builders resolve it from each
    // member's own card). Never fall through to the 1:1 scalar in a group, or a
    // preference carried in from a previous 1:1 (e.g. a "enjoys being dirty"
    // character) would stay stale and invert every group member's hygiene.
    if (_activeGroup != null) {
      return _activeCharacter?.frontPorchExtensions?.enjoysLowHygiene ?? false;
    }
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

  // ── Web/mobile Chance Time surface ──────────────────────────────────────
  // The desktop pops its wheel from the one-shot [chanceTimePendingTrigger] via
  // a ChangeNotifier. Web clients (which drive the same shared ChatService over
  // HTTP/WS) have no such hook and no spinning wheel, so they observe the park
  // through these accessors and resolve it with [acceptPendingChanceTime]. All
  // of this is UI-coordination glue for the completer above — the simulation is
  // untouched, so 1:1/group parity is unaffected.

  /// True from the moment a Chance Time parks [sendMessage] until it is
  /// accepted. The durable signal the web surface uses to show — and, after a
  /// phone wakes and reconnects, re-show — the reveal modal.
  bool get isAwaitingChanceTime =>
      _chanceTimeCompleter != null && !_chanceTimeCompleter!.isCompleted;

  /// The speaker a Chance Time event is attributed to: the upcoming group
  /// speaker, else the 1:1 host. Shared by the desktop wheel overlay and the
  /// web accept path so both attribute the event identically.
  String get chanceTimeSpeakerName =>
      nextCharacter?.name ?? activeCharacter?.name ?? 'Character';

  /// The pre-picked pending event with `{{char}}` resolved, for the web reveal
  /// modal. Null when nothing is parked.
  String? get webChanceTimeDisplay =>
      _webChanceTimeEvent?.replaceAll('{{char}}', chanceTimeSpeakerName);

  /// Web/mobile "Accept Your Fate": applies the pre-picked pending event using
  /// the same attribution the desktop wheel uses, then lets generation resume.
  /// No-op if nothing is parked (e.g. the desktop already accepted).
  Future<void> acceptPendingChanceTime() async {
    final raw = _webChanceTimeEvent;
    if (raw == null) return;
    await applyChanceTimeResult(raw, chanceTimeSpeakerName);
  }

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

  /// Set the LLMProvider after construction (to break circular dependency in provider tree).
  void setLLMProvider(LLMProvider provider) {
    _llmProvider = provider;
    // Backend switches and local-engine ready transitions flow through the
    // provider — retest tool support when the identity changes and is ready.
    provider.addListener(_onBackendIdentityMaybeChanged);
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

  /// [imageBytes] optionally attaches a photo (already downscaled+PNG-encoded
  /// by the composer) to this user turn. The bytes are saved to disk HERE,
  /// after all guards pass, so a guard bail can never orphan a file. The photo
  /// renders inline in the bubble, rides along as pixels on this turn's
  /// generation when the model can see (see [buildTurnImages]), and is
  /// described in the flattened history for later turns.
  Future<void> sendMessage(String text, {Uint8List? imageBytes}) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        (text.trim().isEmpty && imageBytes == null)) {
      return;
    }
    // Don't let a user turn start while forked-in entrances are still playing —
    // it would race the one-shot entrance directive / turn positioning.
    if (_entrancesInFlight) return;
    // Likewise, don't race an in-flight Scene Guest creation/entrance (the mint
    // runs a separate LLM call that doesn't set _isGenerating).
    if (_guestBusy) return;
    // A photo turn's captioning windows run while _isGenerating is false; this
    // guard stops a second send from interleaving them (see isPhotoTurnInFlight).
    if (_photoTurnInFlight) return;
    // One-shot absence acknowledgment: pending survives exactly the first
    // user turn after load (all of that turn's prompt builds see it); the
    // second turn clears it for good.
    if (_absenceAckPending) {
      if (_absenceAckConsumed) {
        _absenceAckPending = false;
      } else {
        _absenceAckConsumed = true;
      }
    }
    // Start-of-turn clear: cancelRealismEval only sets this while an eval is
    // live, and each turn's consumers clear it — but this guarantees a stray
    // set flag can never bleed into THIS turn and abort a reply the user did
    // not cancel.
    _realismEvalCancelled = false;
    clearSuggestions();

    // A new message while an /image prompt review is parked cancels it —
    // the desktop dialog is modal, but the web modal can be typed around.
    resolveImagePromptReview(null);

    // User is interacting — clear any pending auto-response state
    _pendingIdleCue = null;

    // ── Slash Command Handling (delegated to leaf) ──────────────────────
    // Skipped when a photo is attached: an attach makes the intent "send a
    // message" unambiguous, and consuming the text as a command would drop
    // the attachment silently.
    final trimmed = text.trim();
    if (imageBytes == null &&
        trimmed.startsWith('/') &&
        _characterRepository != null) {
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

    // Save the attachment to disk only now that every guard has passed — the
    // composer passes bytes, not a path, so a guard bail above can't orphan a
    // file. Null when there are no bytes / the image service isn't wired.
    final imagePath = await _persistTurnImage(imageBytes);

    final senderName = _userPersonaService.persona.name;
    final userMsg = ChatMessage(
      text: text,
      sender: senderName,
      isUser: true,
      metadata: imagePath != null
          ? {'is_user_image': true, 'image_path': imagePath}
          : null,
    );
    // Session token for the caption writes below — captured NOW so a chat
    // switch anywhere during the (long) turn voids the stamp+save.
    final sessionToken = _currentSessionId;
    _messages.add(userMsg);
    await _saveChat();
    notifyListeners();

    // ── Dreams (Living Time §1) — a night passed since the last turn, so the
    // dream surfaces before this morning's exchange. Owner = the character
    // who ended the previous day (last assistant speaker): ONE rule for 1:1
    // and group, so parity holds by construction. Any failure skips silently
    // (the local-model floor: a bad dream is worse than no dream).
    _dreamService.checkRollover(
      sessionId: _currentSessionId,
      dayCount: _timeService.dayCount,
    );
    if (_dreamService.pending && _currentSessionId != null) {
      _dreamService.clear();
      try {
        String? lastCharId;
        var lastSpeakerFound = false;
        for (final m in _messages.reversed) {
          if (!m.isUser &&
              m.sender != 'System' &&
              m.activeMetadata?['is_dream'] != true) {
            lastCharId = m.characterId;
            lastSpeakerFound = true;
            break;
          }
        }
        final ownerCard = !lastSpeakerFound
            ? null
            : lastCharId == null
            ? _activeCharacter
            : (_groupCharacters
                      .where((c) => _getCharacterIdFromCard(c) == lastCharId)
                      .firstOrNull ??
                  _activeCharacter);
        if (ownerCard != null) {
          final ownerId = _getCharacterIdFromCard(ownerCard);
          final cards = await _journalStore.cardsFor(
            _currentSessionId!,
            ownerId,
          );
          final sorted = [...cards]
            ..sort(
              (a, b) => JournalPhysics.cooledHeat(
                b,
              ).compareTo(JournalPhysics.cooledHeat(a)),
            );
          final dream = await _dreamService.generateDream(
            characterName: ownerCard.name,
            memoryFragments: [for (final c in sorted.take(5)) c.content],
            fixation: _relationshipService.activeFixation,
            emotion: _characterEmotion,
            recap: _summary.length > 300
                ? _summary.substring(0, 300)
                : _summary,
            weatherLine: switch (currentWeather) {
              null => null,
              final w => WeatherEngine.prose(w),
            },
            ambitions: ownerCard.frontPorchExtensions?.ambitions ?? const [],
          );
          if (dream != null) {
            _messages.insert(
              _messages.length - 1,
              ChatMessage(
                text: dream,
                sender: ownerCard.name,
                isUser: false,
                characterId: lastCharId,
                metadata: {'is_dream': true},
              ),
            );
            notifyListeners();
            await _journalStore.addCard(
              sessionId: _currentSessionId!,
              characterId: ownerId,
              content: dream,
              category: 'moment',
              kind: 'dream',
              emotionLabel: _characterEmotion.isEmpty
                  ? null
                  : _characterEmotion,
              storyDay: _timeService.dayCount,
              storyClock: _timeService.storyClockIso,
              maxCards: _storageService.memorySettings.journalMaxCards,
            );
            await _saveChat();
          }
        }
      } catch (e) {
        debugPrint('[Dreams] skipped: $e');
      }
    }

    // ── Blind-model photo fallback: caption BEFORE generating ───────────────
    // Vision-capable models return true immediately (their pixels ride along
    // and their caption runs post-turn); blind models run the offline
    // captioner so this turn's history already carries the gist. Returns false
    // when the scene changed during the (multi-second) caption await — abort
    // rather than run decay/realism/generation against a newly loaded chat.
    if (imagePath != null) {
      final stillHere = await runBlindPhotoCaption(
        userMsg,
        imagePath,
        sessionToken,
      );
      if (!stillHere) return;
    }

    // Reset the idle timer — user is interacting
    _cancelIdleTimer();

    // Clear the new chat flag after first user message to allow memory retrieval
    if (_isNewChat) {
      _isNewChat = false;
      debugPrint('[sendMessage] Cleared new chat flag, memories now allowed');
    }

    // {{idle_duration}} clock: the user just spoke.
    _lastUserMessageAt = DateTime.now();

    // Scan for lore keywords (thin to scanner; the user message is already
    // in _messages, so the scanner windows over recent history from there).
    _lorebookScanner.scanLatest();

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
        // Pre-pick the one event the web/mobile reveal modal shows + accepts
        // (the desktop spins its own wheel instead — same pool, same accept).
        final webWheel = _chaosModeService.spinWheelEvents();
        _webChanceTimeEvent = webWheel.isNotEmpty
            ? webWheel.first
            : 'Fate intervenes in an unexpected way.';
        notifyListeners(); // UI observes this to show the wheel
        // Wait for the user to spin + accept fate (completes in applyChanceTimeResult)
        await _chanceTimeCompleter!.future;
        _chanceTimeCompleter = null;
        _webChanceTimeEvent = null;
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

      // Short-term bond decay: 1:1 host only. In group mode the speaker isn't
      // picked yet — the old call here fell back to the FIRST member under
      // random turn order, so member #1 absorbed everyone's decay. The group
      // tick now lives per-speaker inside _evaluateRealismForUpcomingSpeaker,
      // on the pinned speaker's own cadence counter (mirrors needs + nsfw).
      if (_activeGroup == null) {
        _applyMoodDecay();
      }
      // Needs decay for 1:1 always here. For group non-observer, speaker-specific decay
      // (respecting the actual picked speaker for random turn order) is applied inside
      // _evaluateRealismForUpcomingSpeaker after _pickNextGroupCharacter has run.
      if (_activeGroup == null || _observerMode || !_needsSimEnabled) {
        _needsSimulation.tickDecay();
      } else {
        // Group non-obs + needs on: decay is applied per-speaker inside the
        // single eval path (_evaluateRealismForUpcomingSpeaker).
      }
      // Refractory tick for the 1:1 host only. In group mode the speaker
      // hasn't been picked yet — decrementing here mutated whichever member's
      // scalars were still loaded from LAST turn, and the tick was then
      // discarded by _loadGroupRealismIntoScalars, so group cooldowns never
      // actually counted down. The group tick now lives per-speaker in
      // _evaluateRealismForUpcomingSpeaker, right after that speaker's
      // scalars are loaded (mirroring the per-speaker needs decay).
      if (_activeGroup == null) {
        _nsfwService.decrementCooldownIfActive();
      }

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
    // First exchange complete — arm idle timer
    _hasCompletedExchange = true;
    if (_storageService.generationSettings.dynamicResponses) {
      debugPrint(
        '[DynamicResponses] First exchange done, arming idle timer (interval=${_storageService.generationSettings.dynamicResponseInterval}s)',
      );
      _resetIdleTimer();
    }

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
    // promptText (not raw text) so a photo-only turn feeds the director a
    // "[shared a photo]" marker instead of an empty user message.
    await _maybeRunSceneGuestChimeIns(userText: userMsg.promptText);

    // ── Auto-caption the attached photo for future-turn history ─────────────
    // Vision path only (blind models were captioned pre-gen). Runs LAST so the
    // eval never delays the response or guest turns; this turn already saw the
    // pixels, so the caption just lets later turns' history describe the photo.
    if (imagePath != null) {
      await runVisionPhotoCaption(userMsg, imagePath, sessionToken);
    }
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

    _lorebookScanner.scanLatest();
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
        // Timeline integrity: the active variant at this position changed —
        // cards journaled from the other swipe are now phantom.
        _invalidateJournalFrom(messageIndex);
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
      // Timeline integrity — same as the left-swipe branch above.
      _invalidateJournalFrom(messageIndex);
      await _saveChat();
      notifyListeners();
    } else if (messageIndex == _messages.length - 1 && !_isGenerating) {
      // Past last swipe on last message — regenerate
      await regenerateLastMessage();
    }
  }

  void _syncRealismStateForSwipe(ChatMessage msg, int oldIndex, int newIndex) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate
    // timeline — in groups, into the swiped speaker's own _groupRealism entry.
    _restoreRealismStateForSpeaker(msg);
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
      final deleted = _messages[index];
      _messages.removeAt(index);

      // Timeline integrity: the delete rewrites history from [index] on
      // (later positions shift down), so cards citing that region and the
      // pass cursor both roll back — replaces the old cursor-decrement drift
      // fix, which kept phantom cards alive (smoke-test bug 2026-07-21).
      // (Growth uses a DB-backed per-session cursor; it re-reads its stored
      // index on the next pass.)
      _invalidateJournalFrom(index);

      // Time-travel rollback for realism when deleting a character message.
      // Restore from the new last message if it has a snapshot, regardless
      // of whether this was the last message. This ensures needs state
      // (and all realism fields) reset to their previous saved values — in
      // groups, inside the NEW LAST speaker's own _groupRealism entry.
      if (_messages.isNotEmpty) {
        final newLast = _messages.last;
        _restoreRealismStateForSpeaker(newLast);
      }

      // Group: also roll back the DELETED speaker's OWN _groupRealism entry to
      // their previous stamped turn — otherwise that member's bond/trust/needs
      // deltas from the removed message stand forever (the state machine only
      // rewinds whoever is now last). Guards:
      //   • the deleted message must itself carry a realism_state — otherwise
      //     it applied no deltas and rewinding would INVENT older history;
      //   • the sender name must be unambiguous in the roster — restore resolves
      //     by name (_restoreRealismStateForSpeaker), so with two same-named
      //     members it could rewind the wrong one; skip that rare case rather
      //     than corrupt state;
      //   • skip when the deleted speaker is already the new-last (handled
      //     above) or has no earlier stamped turn.
      if (_activeGroup != null &&
          !deleted.isUser &&
          deleted.sender != 'System' &&
          deleted.activeMetadata?['realism_state'] is Map &&
          _groupCharacters.where((c) => c.name == deleted.sender).length == 1 &&
          (_messages.isEmpty || _messages.last.sender != deleted.sender)) {
        for (int i = _messages.length - 1; i >= 0; i--) {
          final m = _messages[i];
          if (m.sender == deleted.sender &&
              m.activeMetadata?['realism_state'] is Map) {
            _restoreRealismStateForSpeaker(m);
            break;
          }
        }
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
      // Timeline integrity: an edit at a journaled position rewrites what
      // the diary already read (smoke-test bug 2026-07-21).
      _invalidateJournalFrom(index);
      await _saveChat();
      notifyListeners();
    }
  }

  /// Timeline-integrity invalidation (Journal): content at [position] was
  /// rewritten — regen, swipe navigation, edit, or delete. Cards citing
  /// positions ≥ [position] describe events that no longer happened, so they
  /// are removed (all diary owners), the pass cursor rolls back so the next
  /// pass re-reads the rewritten window, and a salience kick refreshes the
  /// recap soon. Cheap no-op when the pass never consumed the region: cards
  /// only ever cite positions below the cursor. The recap TEXT may still
  /// carry a stale sentence until the next pass rewrites it — a full recap
  /// rewind is deliberately out of scope (documented, not silent).
  void _invalidateJournalFrom(int position) {
    final sessionId = _currentSessionId;
    if (sessionId == null || position >= _summaryLastIndex) return;
    _summaryLastIndex = position;
    unawaited(
      _journalStore.invalidateCardsCitingFrom(sessionId, position).then((
        removed,
      ) {
        if (removed > 0 && !_disposed) {
          _journalMaintenance.eventKickPending = true;
          debugPrint(
            '[Journal] Timeline rewrite at $position — removed $removed '
            'card(s) citing the discarded region',
          );
          notifyListeners();
        }
      }),
    );
  }

  // ── The Journal recap ("Where we are") ──────────────────────────────
  // The recap reuses the _summary scalar + Sessions.summary persistence the
  // old summary system used, so the public surface below (sidebar, web
  // facade, the growth pass's getRecap cb) is unchanged. The generator is
  // the Journal maintenance pass (journal_maintenance leaf), which also
  // produces the per-character memory cards in the same LLM call.

  /// Manually set the recap text.
  void setSummary(String text) {
    _summary = text;
    _saveChat();
    notifyListeners();
  }

  /// Pause or resume the automatic Journal maintenance pass.
  void setSummaryPaused(bool paused) {
    _summaryPaused = paused;
    notifyListeners();
  }

  /// Force an immediate Journal maintenance pass (cards + recap), bypassing
  /// the interval. Backs the sidebar/web "Regenerate" button (name kept for
  /// the existing public surface).
  Future<void> forceSummaryUpdate() async {
    if (_isSummaryGenerating) return;
    await _journalMaintenance.runMaintenancePass(force: true);
  }

  /// Train B — promise/debt ledger pass (fire-and-forget). Runs after a
  /// normal generation when realism + journal are on. Detects new
  /// commitments or kept/broken resolutions for the current speaker's diary.
  void _maybeRunPromiseDebtPass() {
    if (!_realismEnabled) return;
    if (!_storageService.memorySettings.journalEnabled) return;
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final charId = _getCurrentSpeakerIdForRealism();
    if (charId.isEmpty) return;

    String characterName = _activeCharacter?.name ?? 'the character';
    if (_activeGroup != null && !_observerMode) {
      final card = _groupCharacters
          .where((c) => _getCharacterIdFromCard(c) == charId)
          .firstOrNull;
      if (card != null) characterName = card.name;
    }

    final recent = _messages.length < 2
        ? (_messages.isEmpty ? '' : _messages.last.displayText)
        : _messages.reversed
              .take(4)
              .toList()
              .reversed
              .map((m) => '${m.sender}: ${m.displayText}')
              .join('\n');
    if (recent.trim().isEmpty) return;

    unawaited(
      _promiseDebtService.evaluateTurn(
        sessionId: sessionId,
        characterId: charId,
        characterName: characterName,
        userName: _userPersonaService.persona.name,
        recentExchange: recent,
        receiptPosition: _messages.isEmpty ? null : _messages.length - 1,
        storyDay: _timeService.dayCount,
        storyClock: _timeService.storyClockIso,
      ),
    );
  }

  /// Check if a Journal maintenance pass is due and trigger it non-blockingly.
  /// Cadence (design §4.2): user messages since the _summaryLastIndex cursor
  /// vs the journalInterval setting, PLUS an immediate pass when the window
  /// holds a significant engine-stamped event (big bond/trust swing, trust
  /// repair, Chance Time) or an objective completed (the eventKickPending
  /// flag, set pre-generation, consumed here post-generation so the pass
  /// never competes with the main LLM call). Guards mirror the old summary
  /// coordinator.
  void _maybeRunJournalPass() {
    if (!_storageService.memorySettings.journalEnabled) return;
    if (_summaryPaused) return;
    if (_isSummaryGenerating) return;
    if (_llmProvider == null) return;

    final windowStart = _summaryLastIndex.clamp(0, _messages.length);
    int userMessagesSincePass = 0;
    for (int i = windowStart; i < _messages.length; i++) {
      if (_messages[i].isUser) userMessagesSincePass++;
    }
    if (userMessagesSincePass == 0) return;

    final due =
        userMessagesSincePass >= _storageService.memorySettings.journalInterval;
    final eventKick =
        _journalMaintenance.eventKickPending ||
        JournalPhysics.hasSalientEvent(_messages.sublist(windowStart));

    if (due || eventKick) {
      // Fire and forget — don't await. The pass consumes eventKickPending
      // itself once it actually starts, so a parked review batch (or an
      // already-running pass) can't silently eat the kick.
      _journalMaintenance.runMaintenancePass();
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

  /// Coordinator for the periodic background evals (now just Scene Guest cast
  /// detection). User-fact extraction and chat summaries were replaced by the
  /// Journal maintenance pass (_maybeRunJournalPass); character evolution was
  /// replaced by the growth pass (_maybeRunGrowthPass in
  /// chat_service_growth.dart), which has its own cursor-based cadence.
  void _maybeRunPeriodicEvals() {
    // Scene Guest cast detection (1:1 only). Runs on its own cadence and
    // fires-and-forget so it never blocks the turn. See _maybeRunCastDetection.
    _maybeRunCastDetection();
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

  // ── Growth Rings runtime state (full feature in growth_service.dart leaf
  // + chat_service_growth.dart part; docs/design/growth-rings.md) ──

  /// Transient re-entrancy/spinner flag for the growth pass. Defensively
  /// zeroed on all reset/new-chat/0-session/group/setActive/load/fork paths
  /// (the same "keep reset blocks in sync" sites the old evolution flag
  /// used). Ring/legacy data itself lives in the session-scoped GrowthStore
  /// cache, invalidated/refreshed at the context-switch sites.
  bool _isGrowthPassRunning = false;

  /// Kept as an instance getter (not in the growth part) because test fakes
  /// (`FakeChatService implements ChatService`) override it — extension
  /// getters are statically dispatched and cannot be overridden via
  /// `implements`.
  bool get isGrowthPassRunning => _isGrowthPassRunning;

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

    // Transient banner only — NEVER a chat message. The old code appended an
    // "evaluation interrupted" line attributed to the character, which then
    // permanently rode chat history, prompts, RAG, and journal windows.
    _setGuestStatus(
      'Realism evaluation cancelled — no reply was generated. '
      'Regenerate (or send again) to retry.',
    );

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
  // for main prompt assembly — the _realismStateInjection composer owns the words-only
  // "[How <Name> is right now: …]" block (see realism_state_injection.dart + design doc).
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

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelIdleTimer();
    _guestStatusClearTimer?.cancel();
    _characterRepository?.removeListener(_onCharacterLibraryChanged);
    _storageService.removeListener(_onBackendIdentityMaybeChanged);
    _llmProvider?.removeListener(_onBackendIdentityMaybeChanged);
    _toolProbe.removeListener(notifyListeners);
    super.dispose();
  }
}
