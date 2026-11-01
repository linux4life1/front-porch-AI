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
import 'package:front_porch_ai/services/chat/chat_defaults.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// User-facing notice for "managed backend stopped + auto-start off". A
/// const so [TurnEntry.abortIfBackendDown]'s dedupe can compare against the
/// last message, and the send spine can tell a refused turn from a reply.
const kBackendDownNotice =
    'Backend is not running. Start it in Settings → Backend, '
    "or enable 'Auto-start on chat open'.";

/// A turn's admission and the helpers the turn path builds on demand: the
/// Continue speaker check ([admitTurn]), Approach A′ soft members
/// ([isLiteTurn]), the refractory tick after the clock, the slash-command
/// handler, the guest chime-in director and the cast detector with its
/// periodic scan. All cross-state routes back through the doors, so the
/// leaves they build never import the chat service.
class TurnEntry {
  TurnEntry(this._e);

  final TurnEngine _e;

  /// The slash-command dispatcher, built on first use.
  ChatCommandHandler? _commandHandlerCache;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  EntryDoor get _entry => _d.doors.entry();
  SessionStore get _sessions => _d.doors.sessions();
  CastDoor get _cast => _d.doors.cast();
  PromptAssembler get _prompts => _d.doors.prompts();
  MediaDoor get _media => _d.doors.media();
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  String _getCharacterIdFromCard(CharacterCard card) =>
      _session.characterIdFor(card);

  GroupChat? get _activeGroup => _session.activeGroup;
  Future<void> _addGuestWithStatus({
    required String displayName,
    CharacterCard? existing,
    Future<GuestMintResult> Function(void Function(String step) onStatus)? mint,
  }) => _cast.guests.addGuestWithStatus(
    displayName: displayName,
    existing: existing,
    mint: mint,
  );
  AfterglowPass get _afterglow => _g.afterglow;
  set _consecutiveAutoResponses(int v) =>
      _cast.idle.consecutiveAutoResponses = v;
  bool get _directing => _entry.director.directing;
  String get _evalBackendIdentity => _g.transport.backendIdentity;
  ExpressionService get _expressionService => _g.expression;
  FireToolEval get _fireToolEval => _g.transport.fireToolEval;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  GroupChatRepository? get _groupChatRepository => _entry.groupRepository;
  bool _isGuestAuthoredMessage(ChatMessage m) =>
      _cast.guests.isGuestAuthoredMessage(m);
  Future<GuestMintResult> _mintSceneGuest(
    String name,
    String concept, {
    void Function(String step)? onStatus,
  }) => _cast.joins.mintSceneGuest(name, concept, onStatus: onStatus);
  void _releaseHeldAway(CharacterCard card) => _cast.away.releaseHeldAway(card);
  Future<void> _resolveSceneGuestCards() =>
      _cast.guests.resolveSceneGuestCards();
  Future<void> _saveChat({bool replaceAll = false}) =>
      _sessions.save(replaceAll: replaceAll);
  bool _sceneChanged(String? token) => _cast.sceneChanged(token);
  SceneGuestState get _sceneGuest => _cast.guests.state;
  CharacterCard? _sceneGuestForMessage(ChatMessage m) =>
      _cast.guests.sceneGuestForMessage(m);
  void _setGuestStatus(
    String? msg, {
    bool isError = false,
    bool sticky = false,
  }) => _cast.guests.setStatus(msg, isError: isError, sticky: sticky);
  ToolTransportProbe get _toolProbe => _g.transport.probe;

  /// True when generation must not proceed: the managed local backend is not
  /// running and auto-start on chat open is off. Appends ONE system notice
  /// naming the toggle (deduped against the last message so group
  /// auto-advance and idle retries can't stack copies), so every entry point
  /// — send, regenerate, continue, swipe, group advance, impersonate — fails
  /// the same friendly way instead of a connection error or silent cancel.
  ///
  /// Deliberately does NOT _saveChat: the notice is transient status, and
  /// persisting here from inside generate would write the transcript
  /// mid-mutation for callers that pop a message before generating (regen
  /// popped the last AI reply, abort saved the hole — permanent data loss).
  /// Callers that pop MUST also run this check BEFORE their pop (regen paths
  /// do); this deep guard is the backstop for the non-mutating entries.
  Future<bool> abortIfBackendDown() async {
    if (_llmProvider?.hasManagedProcess != true ||
        _storageService.backendSettings.autostartOnChatOpen ||
        _llmProvider?.hasAnyManagedProcessRunning == true) {
      return false;
    }
    if (_session.messages.isEmpty ||
        _session.messages.last.text != kBackendDownNotice) {
      _session.messages.add(statusBannerMessage(kBackendDownNotice));
      _d.notify();
    }
    return true;
  }

  /// The speakers to run the turn with, or null when it may not run: the
  /// backend is down, or a Continue whose speaker has left or is unclear.
  ///
  /// Every refusal (and a throw) leaves through the one `finally`, which
  /// ends the turn that never ran. A refusal that only returned left the
  /// flag up: Send then did nothing and a chat switch waited forever.
  Future<({CharacterCard? guest, CharacterCard? force})?> admitTurn(
    GenerationMode mode,
    CharacterCard? guestSpeaker,
    CharacterCard? forceSpeaker,
  ) async {
    var admitted = false;
    try {
      if (await abortIfBackendDown()) return null;
      // Continue is regen's sibling for WHO is speaking. Infer guest / group
      // member from the bubble; refuse rather than guess.
      if (mode == GenerationMode.continue_ && _session.messages.isNotEmpty) {
        final last = _session.messages.last;
        guestSpeaker ??= _sceneGuestForMessage(last);
        if (guestSpeaker == null && _isGuestAuthoredMessage(last)) {
          _setGuestStatus(
            'Can’t continue "${last.sender}" — they have left the scene.',
            isError: true,
          );
          return null;
        }
        if (guestSpeaker == null && _activeGroup != null) {
          forceSpeaker ??= _e.replay.resolveGroupSpeakerForMessage(last);
          if (forceSpeaker == null) {
            _setGuestStatus(
              'Can’t continue "${last.sender}" — who said it is ambiguous.',
              isError: true,
            );
            return null;
          }
        }
      }
      admitted = true;
      return (guest: guestSpeaker, force: forceSpeaker);
    } finally {
      if (!admitted) {
        // No turn will run — terminate BOTH live streams. The sentence
        // stream has no error sentinel: `call_overlay` closes its controller
        // on '__DONE__' alone, and `TtsService.speakStreaming` blocks in
        // `await for` until that close, so a silent bail freezes a voice call
        // on "Thinking…" with the mic never re-armed. The phone's chat ends
        // its pending reply on the token sentinel.
        _p.tokenBroadcast.add('__ERROR__');
        _p.sentenceBroadcast.add('__DONE__');
        _p.isGenerating = false;
        _d.notify();
      }
    }
  }

  /// 1:1 guest turn **or** a soft group member speaking. Do not set
  /// `guestSpeaker` for the latter — that skip would drop Away / pick.
  bool isLiteTurn(GenTurn t) => _prompts.isLiteTurn(t);

  /// After the clock commits; body in [AfterglowPass.tickAfterClock]. A lite
  /// beat (guest or soft member) has no speaker refractory to open.
  void tickRefractoryAfterClock(GenTurn t) => _afterglow.tickAfterClock(
    t.mode,
    speakerIdOf: () =>
        isLiteTurn(t) ? null : _getCharacterIdFromCard(t.speakingCharacter),
    reply: () => t.streamTarget,
  );

  /// Slash-command dispatcher (lazily built). All cross-state mutations route
  /// back here via small callbacks so the handler stays pure and never imports
  /// the chat service or any heavy service.
  ChatCommandHandler commandHandler() {
    return _commandHandlerCache ??= ChatCommandHandler(
      setExpression: (label) => _expressionService.setManualExpression(label),
      activeCharacterIsSet: () =>
          _session.activeCharacter != null && _activeGroup == null,
      getSceneGuestCards: () => _sceneGuest.cards,
      setPendingGuestDeparture: (name) => _sceneGuest.pendingDeparture = name,
      onSystemMessage: (message) =>
          // Surface usage hints / errors as the transient inline banner instead
          // of a saved 'System' chat message (no litter). '⚠' prefix = error.
          _setGuestStatus(message, isError: message.startsWith('⚠')),
      generatePrimaryTurn: () => _e.generate(GenerationMode.normal),
      createGuest: (name, concept) => _addGuestWithStatus(
        displayName: name,
        mint: (onStatus) => _mintSceneGuest(name, concept, onStatus: onStatus),
      ),
      exitGuest: (guest) async {
        _sceneGuest.ids.remove(guest.dbId);
        await _resolveSceneGuestCards();
        await _saveChat();
      },
      getJoinableCharacters: () => _cast.joins.joinableGuestCharacters,
      joinGuest: _cast.joins.joinSceneGuest,
      joinFull: _cast.joins.joinFull,
      promoteScene: _cast.joins.promoteSceneToFull,
      requestGuestPicker: (filter, full) {
        _sceneGuest.pendingPickerFilter = filter;
        _sceneGuest.pendingPickerFull = full;
        _d.notify();
      },
      runCastScan: runCastDetectionNow,
      speakGuest: _cast.guests.speakGuestNow,
      getHostCharacter: () => _session.activeCharacter,
      isTurnBusy: () => _e.isTurnBusy || _sceneGuest.busy,
      armExitUndo: _cast.guests.armExitUndo,
      getGroupMembers: () =>
          _activeGroup != null ? _groupCharacters : const <CharacterCard>[],
      getGroupJoinableCharacters: () => _cast.joins.joinableGroupCharacters,
      removeGroupMember: (member) async {
        final repo = _groupChatRepository;
        if (repo == null) return false;
        if (!_cast.roster.canRemoveCastMember) {
          _setGuestStatus(kDirectorCastFloorNote, isError: true);
          return true; // answered: the floor note says why
        }
        // Narrate the member's goodbye + arm a deferred-deletion UNDO; the real
        // removal commits when the user continues (mirrors the Lite-NPC exit).
        return _cast.roster.exitGroupMember(member, repo);
      },
      speakGroupMember: (member) async {
        // /speak <name> in a full group: force that member to take their turn
        // now (jump the rotation), including Away/at-work (forceSpeaker).
        if (_activeGroup == null) return;
        if (_e.isTurnBusy) {
          _setGuestStatus('Busy — try again in a moment.', isError: true);
          return;
        }
        _releaseHeldAway(member);
        _session.groupManager?.setNextSpeaker(member);
        final tipBefore = _session.messages.lastOrNull;
        await _e.generate(GenerationMode.normal, forceSpeaker: member);
        // forceSpeaker skips the pick, so close the turn here once the
        // member's reply landed: the rotation carries on after them. A
        // refused or failed turn keeps them up next for the retry.
        final tip = _session.messages.lastOrNull;
        final said = tip == null || identical(tip, tipBefore) || tip.isUser
            ? null
            : _e.replay.resolveGroupSpeakerForMessage(tip);
        final spoke =
            said != null &&
            _getCharacterIdFromCard(said) == _getCharacterIdFromCard(member);
        if (spoke) {
          _session.groupManager?.clearForcedSpeaker();
          _session.groupManager?.advanceAfterRegeneration(member);
        }
      },
      isGroupTurnOrderRandom: () => _entry.members.isGroupTurnOrderRandom,
      setGroupTurnOrder: (random, customOrder) =>
          _entry.members.setGroupTurnOrder(random, customOrder),
      configureAfk: (enabled, maxMessages, intervalSeconds) {
        // Drive the same persisted Dynamic Responses settings the sidebar panel
        // uses (single source of truth — no parallel AFK state). Returns the
        // effective values so the handler can word its confirmation.
        final gen = _storageService.generationSettings;
        if (!enabled) {
          gen.setDynamicResponses(false);
          _cast.idle.pauseDynamicResponses();
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
        _cast.idle.resumeDynamicResponses();
        return (
          enabled: true,
          maxMessages: gen.dynamicResponseMaxMessages,
          intervalSeconds: gen.dynamicResponseInterval,
        );
      },
      generateImage: (args) => _media.ensureImageCommand().handle(args),
      director: DirectorCommands(
        isGroup: () => _activeGroup != null,
        hasSceneGuests: () => _sceneGuest.cards.isNotEmpty,
        isDirecting: () => _directing,
        promoteSceneToGroup: _cast.joins.promoteSceneToFull,
        stepUserOffStage: _cast.stage.stepUserOffStage,
        stepUserOnStage: _cast.stage.stepUserOnStage,
        getCast: () => _groupCharacters,
        setWhisper: (member, text) => _cast.stage.setDirectorWhisper(
          _getCharacterIdFromCard(member),
          text,
        ),
        setGoal: _cast.stage.setDirectorGoal,
        narrate: _cast.stage.narrateScene,
        onSystemMessage: (m) => _setGuestStatus(m, isError: m.startsWith('⚠')),
      ),
    );
  }

  /// Auto chime-in director (lazily built). Pure leaf — all cross-state routes
  /// back via callbacks so it never imports the chat service. Reuses the existing
  /// `LlmEvalEngine` fire/strip/extract surface for its relevance gate (no new
  /// LLM-firing path) and only triggers parity-safe guest turns.
  SceneGuestDirector sceneGuestDirector() {
    return _sceneGuest.director ??= SceneGuestDirector(
      getSceneGuestCards: () => _sceneGuest.cards,
      generateGuestTurn: _cast.guests.generateGuestTurn,
      getLatestAssistantText: () {
        for (final m in _session.messages.reversed) {
          if (!m.isUser && m.sender != 'System') return m.displayText;
        }
        return '';
      },
      fireGateEval: (prompt) => _g.transport.fireLLMEval(
        prompt,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'guest_gate',
      ),
      stripThinkBlocks: stripEvalThinkBlocks,
      extractJsonBool: evalJsonBool,
      getHostName: () => _session.activeCharacter?.name ?? 'the character',
      isEnabled: () => _cast.guests.autoChimeEnabled,
    );
  }

  /// Cast detector (lazily built). Pure leaf — all cross-state routes back via
  /// callbacks so it never imports the chat service. Reuses the existing
  /// `LlmEvalEngine` fire/strip surface (no new LLM-firing path).
  CastDetector castDetector() {
    return _sceneGuest.castDetector ??= CastDetector(
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
        for (final m in _session.messages.reversed) {
          if (!m.isUser &&
              m.sender != 'System' &&
              !_isGuestAuthoredMessage(m)) {
            out.add(m.displayText);
          }
          if (out.length >= 6) break;
        }
        return out.reversed.toList();
      },
      fireLLMEval: (prompt) => _g.transport.fireLLMEval(
        prompt,
        repeatPenalty: kScalarEvalRepeatPenalty,
        label: 'cast',
      ),
      stripThinkBlocks: stripEvalThinkBlocks,
      getHostName: () =>
          _session.activeCharacter?.name ??
          _entry.director.nextCharacter?.name ??
          _groupCharacters.firstOrNull?.name ??
          '',
      getUserName: () => _userPersonaService.persona.name,
      getSceneGuestNames: () => [
        ..._sceneGuest.cards.map((g) => g.name),
        ..._groupCharacters.map((c) => c.name),
      ],
      getOfferedOrIgnoredNames: () => _sceneGuest.offeredOrIgnoredNames,
    );
  }

  /// Coordinator for the periodic background evals (now just Scene Guest cast
  /// detection). User-fact extraction and chat summaries were replaced by the
  /// Journal maintenance pass (_maybeRunJournalPass); character evolution was
  /// replaced by the growth pass (GrowthDesk.maybeRunGrowthPass), which has
  /// its own cursor-based cadence.
  void maybeRunPeriodicEvals() {
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
    // The one gate, and it is the AUTOMATIC path only. `/scan` deliberately
    // still works with this off: the complaint this switch answers is being
    // interrupted by offers nobody asked for, and typing `/scan` is asking.
    if (!_storageService.realismSettings.sceneGuestDetectionEnabled) return;
    if (_session.activeCharacter == null && _activeGroup == null) return;
    if (_sceneGuest.pendingDetection != null) return; // one offer at a time

    _sceneGuest.turnsSinceCastScan++;
    if (_sceneGuest.turnsSinceCastScan < kCastScanInterval) return;
    _sceneGuest.turnsSinceCastScan = 0;

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
    if (_session.activeCharacter == null && _activeGroup == null) return false;
    if (_sceneGuest.pendingDetection != null) return false;
    _sceneGuest.turnsSinceCastScan = 0;
    // Re-resolve first so any guest whose library card was deleted is pruned
    // from the scene list — otherwise the detector still treats them as "already
    // a scene guest" and silently rejects re-detecting them (the exact symptom
    // of deleting a guest's card then /scan-ning for them again).
    await _resolveSceneGuestCards();
    // A manual scan is an explicit "look again", so forget prior in-session
    // dismissals/offers — otherwise a character you ignored (or added then
    // deleted) can never be re-surfaced without starting a fresh chat. Names
    // still genuinely in the scene are excluded by the live scene-guest filter.
    _sceneGuest.offeredOrIgnoredNames.clear();
    final detected = await _performCastScan();
    return detected != null;
  }

  /// Run one detection pass and, on a fresh hit, raise the offer popup (set the
  /// pending flag + notify). Shared by the automatic per-turn path and the
  /// manual `/scan` command so there is exactly ONE detect→surface path.
  /// Returns the surfaced candidate, or null when nothing was found.
  Future<DetectedCharacter?> _performCastScan() async {
    final token =
        _session.currentSessionId; // the scan is slow; the chat may switch
    final detected = await castDetector().detect();
    if (detected == null) return null;
    // Bail if the chat/character/session changed (or we were disposed) during
    // the eval — otherwise a character detected from chat A's narration would
    // pop as an offer inside chat B and get minted into B's scene.
    if (_sceneChanged(token)) return null;
    if (_sceneGuest.pendingDetection != null) return null;
    // Mark as offered immediately so a later scan won't re-propose it even if
    // the user leaves the popup open.
    _sceneGuest.offeredOrIgnoredNames.add(detected.name.trim().toLowerCase());
    _sceneGuest.pendingDetection = detected;
    _d.notify();
    return detected;
  }
}
