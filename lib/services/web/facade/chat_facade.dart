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

import 'dart:io';
import 'dart:typed_data';

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart'
    show withoutCity96Ask;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat/chat.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/facade/chat_session_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Thin adapter over [ChatService] for the rewritten web server. Mirrors the
/// legacy chat handlers' JSON contract and pushes a `chat_updated` signal over
/// the WebSocket hub after any state-changing action so clients refetch state.
class ChatFacade {
  ChatFacade(
    this._chat,
    this._characters,
    this._personas,
    this._hub,
    this._groups, {
    File? Function(String name)? resolveSavedImage,
    LLMProvider? llm,
  }) : _resolveSavedImage = resolveSavedImage,
       _llm = llm;

  /// Live LLM connection flag for the chat-input placeholder. Null in tests
  /// that construct a facade without a provider — treated as ready so they
  /// do not inherit a "No API connection" hint.
  final LLMProvider? _llm;

  /// Resolves a saved generated image's basename to its file (with the
  /// traversal guard) — wired to [ImageFacade.savedImageFile] by the host so
  /// the guard lives in one place.
  final File? Function(String name)? _resolveSavedImage;

  final ChatService _chat;

  // Slice 7: scene-mint endpoints act through the chat's own seam.
  ChatService get chat => _chat;
  final CharacterRepository _characters;
  final UserPersonaService? _personas;
  final StreamHub? _hub;
  final GroupChatRepository? _groups;

  /// Realism-READ leaf (host snapshot + per-member participant realism). Pure
  /// reads of [ChatService]; co-located 1:1/group parity pair lives there.
  late final ChatRealismRead _realism = ChatRealismRead(_chat);

  late final ChatSessionFacade _sessions = ChatSessionFacade(
    _chat,
    _characters,
    _notify,
  );

  late final ChatStateSnapshot _snapshot = ChatStateSnapshot(
    _chat,
    _characters,
    _personas,
    _hub,
    _llm,
    _realism,
  );

  late final ChatHistoryActions _history = ChatHistoryActions(
    _chat,
    _hub,
    _notify,
    resolveSavedImage: _resolveSavedImage,
  );

  late final ChatPersonas _personaOps = ChatPersonas(_personas, _chat, _notify);

  /// Full chat state payload (matches legacy `/api/chat/state`).
  Map<String, dynamic> state() => _snapshot.build();

  /// Context Budget payload (desktop ContextViewerDialog parity): per-section
  /// token estimate + the REAL text each section contributed to the last
  /// assembled prompt. Additive endpoint — old clients simply never call it.
  /// The chat's last send, or with [index] the prompt record of that reply
  /// (null when the reply has none).
  Map<String, dynamic>? contextBudget({int? index}) {
    final snap = index == null ? null : _chat.replyContextSnapshot(index);
    if (index != null && snap == null) return null;
    final texts = snap?.sections ?? _chat.lastPromptSections;
    final at = snap != null ? snap.assembledAt : _chat.promptBudgetAssembledAt;
    return {
      'contextLimit': snap?.contextLimit ?? _chat.contextSize,
      'source': snap != null ? 'reply' : _chat.promptBudgetSource.name,
      'assembledAt': at?.toIso8601String(),
      if (snap != null) 'textPruned': snap.sections.isEmpty,
      'droppedMessages': snap?.droppedMessages ?? _chat.promptDroppedMessages,
      'sections': [
        for (final e in (snap?.budget ?? _chat.lastPromptBudget).entries)
          {'label': e.key, 'tokens': e.value, 'text': texts[e.key] ?? ''},
      ],
    };
  }

  /// Rebuild a live estimate from the open chat (no model call).
  Future<Map<String, dynamic>> refreshContextBudget() async {
    await _chat.estimateContextBudgetNow();
    return contextBudget()!;
  }

  /// Re-probe the current backend+model's tool-calling support (the web
  /// pill's tap-to-retest). Returns the fresh verdict.
  Future<Map<String, dynamic>> testToolCalling() async {
    await _chat.testToolCalling();
    return _chat.toolSupportJson;
  }

  /// Realism for a single cast participant (focus-scoped sidebar). Delegates to
  /// the [ChatRealismRead] leaf, which co-locates the host snapshot and the
  /// per-member branch (the 1:1-vs-group parity pair).
  Map<String, dynamic>? participantRealism(String participantId) =>
      _realism.participantRealism(participantId);

  /// Select the active character by its DB id. Returns false if not found.
  Future<bool> select(String characterId) async {
    final card = _characters.characters
        .where((c) => c.dbId == characterId)
        .firstOrNull;
    if (card == null) return false;
    await _chat.setActiveCharacter(card);
    _notify();
    return true;
  }

  /// Next older page of the open chat (scroll-up). No-op when the
  /// window already holds the full transcript.
  Future<bool> loadOlderHistory() async {
    if (!_chat.hasOlderHistory) return false;
    await _chat.loadOlderHistory();
    _notify();
    return true;
  }

  /// ⌘F find-in-chat: engine scan of the open transcript — the single
  /// semantic truth both surfaces highlight against (desktop re-scans
  /// locally through the same engine). Awaits the history backfill, so the
  /// bar shows its wait state while this resolves.
  Future<Map<String, dynamic>> searchTranscript(
    String query, {
    bool regex = false,
    bool caseSensitive = false,
  }) async {
    final outcome = await _chat.findInTranscript(
      query,
      regexMode: regex,
      caseSensitive: caseSensitive,
    );
    return {
      'bad': outcome.badPattern,
      'stale': outcome.stale,
      'capped': outcome.capped,
      'slow': outcome.tooSlow,
      'totalMessages': outcome.totalMessages,
      'matches': [
        for (final m in outcome.matches)
          {
            'messageIndex': m.messageIndex,
            'region': m.region,
            'occurrence': m.occurrenceInRegion,
            'start': m.startInRegion,
            'end': m.endInRegion,
          },
      ],
    };
  }

  /// Open a group chat as the active conversation. Returns false if the group
  /// isn't found or groups aren't wired. Mirrors [select] for parity with the
  /// desktop (which loads the group's last session via setActiveGroup).
  Future<bool> selectGroup(String groupId) async {
    final groups = _groups;
    if (groups == null) return false;
    final group = groups.getById(groupId);
    if (group == null) return false;
    await _chat.setActiveGroup(group, groupRepo: groups);
    _notify();
    return true;
  }

  /// Start a FRESH chat with a character or group under an explicitly chosen
  /// persona — the web library's "Start new chat" card action. Delegates to
  /// [ChatService.startFreshChatWith] so the load-bearing ordering (enter,
  /// then apply persona, then new session) lives in exactly one place, shared
  /// with the desktop context menu. Returns false when the id doesn't resolve.
  Future<bool> startFreshChat({
    String? characterId,
    String? groupId,
    required String personaId,
  }) async {
    if (characterId != null && characterId.isNotEmpty) {
      final card = _characters.characters
          .where((c) => c.dbId == characterId)
          .firstOrNull;
      if (card == null) return false;
      await _chat.startFreshChatWith(character: card, personaId: personaId);
    } else if (groupId != null && groupId.isNotEmpty) {
      final groups = _groups;
      if (groups == null) return false;
      final group = groups.getById(groupId);
      if (group == null) return false;
      await _chat.startFreshChatWith(
        group: group,
        groupRepo: groups,
        personaId: personaId,
      );
    } else {
      return false;
    }
    _notify();
    return true;
  }

  /// A turn started from the phone or the web can end in an image (`/image`,
  /// scene images) that needs the ComfyUI-GGUF loader update. Nobody at the
  /// desktop is waiting on that turn, so it never raises the consent dialog.
  void send(String text, {Uint8List? imageBytes}) {
    withoutCity96Ask(() => _chat.sendMessage(text, imageBytes: imageBytes));
    _notify();
  }

  void stop() {
    _chat.stopGeneration();
    _notify();
  }

  /// Clear a parked `/join` picker (web close without picking).
  void dismissGuestPicker() {
    _chat.dismissGuestPicker();
    _notify();
  }

  /// Answer a suggested scene move: Move runs the desktop's manual
  /// swap (the ONE setChatPlaceSlots writer); Stay records the decline.
  Future<void> answerPlaceMove(bool accept) async {
    if (accept) {
      await _chat.acceptPlaceMove();
    } else {
      _chat.declinePlaceMove();
    }
    _notify();
  }

  /// Web "Accept Your Fate": resolves a parked Chance Time (chaos) event so the
  /// paused send can continue and stream its reply. No-op if nothing is parked.
  Future<void> acceptChanceTime() async {
    await _chat.acceptPendingChanceTime();
    _notify();
  }

  /// Manual SPIN NOW. Parks a pre-picked event; the web reveal modal
  /// opens via the chance_time WS edge (isAwaitingChanceTime).
  bool requestChanceTimeSpin() => _chat.requestManualChanceTime();

  /// The realism-processing overlay's "Stop this reply" button — aborts an
  /// in-flight Realism eval and the reply (mirrors the desktop overlay).
  void cancelRealismEval() {
    _chat.cancelRealismEval();
    _notify();
  }

  /// The UNDO after an `/exit` or a step out to direct (the desktop
  /// SnackBar's twin).
  Future<void> undoLastExit() async {
    await _chat.undoLastExit();
    _notify();
  }

  /// Director Mode's auto-chat Play/Resume, Pause and Stop (the desktop
  /// input row's twin). [pause] keeps the run's turns for a resume.
  void setAutoPlay(bool on, {bool pause = false}) {
    if (on) {
      _chat.startAutoPlay();
    } else if (pause) {
      _chat.pauseAutoPlay();
    } else {
      _chat.stopAutoPlay();
    }
    _notify();
  }

  /// The auto-chat delay (the desktop Director panel slider's twin).
  Future<void> setDirectorDelay(double seconds) async {
    await _chat.setSavedDirectorDelay(seconds);
    _notify();
  }

  Future<void> setDirectorTurnBudget(int turns) async {
    await _chat.setSavedDirectorTurnBudget(turns);
    _notify();
  }

  Future<void> setDirectorGoal(String text) async {
    await _chat.setDirectorGoal(text);
    _notify();
  }

  Future<void> setDirectorWhisper(String memberId, String text) async {
    await _chat.setDirectorWhisper(memberId, text);
    _notify();
  }

  /// The roster's Away / Back (desktop's presence word twin).
  Future<bool> setMemberAway(String memberId, {required bool away}) async {
    final changed = await _chat.setGroupMemberAway(memberId, away: away);
    if (changed) _notify();
    return changed;
  }

  /// The stopped-reply notice's dismiss (desktop's ✕ twin).
  void dismissStoppedReplyNotice() {
    _chat.dismissStoppedReplyNotice();
    _notify();
  }

  /// The goal-check overlay's "Skip goal check" (mirrors the desktop button):
  /// stops only that check; the reply still comes.
  void skipObjectiveCheck() {
    _chat.skipObjectiveCheck();
    _notify();
  }

  void regenerate({String? critique, String? webQuery, String? wikiQuery}) {
    withoutCity96Ask(
      () => _chat.regenerateLastMessage(
        critique: critique,
        webQuery: webQuery,
        wikiQuery: wikiQuery,
      ),
    );
    _notify();
  }

  /// The words the model weighed in reply [index] (KoboldCpp only).
  Map<String, dynamic> tokenAlternatives(int index) =>
      _chat.tokenAlternativesJson(index);

  /// Rewrites reply [index] from [place] with [word]; null once started,
  /// otherwise why it cannot.
  String? pickTokenAlternative(int index, int place, String word) {
    final pick = _chat.tokenAltPick(index, place, word);
    if (pick.at == null) return pick.refusal;
    withoutCity96Ask(() => _chat.rewriteFromAlternative(index, pick.at!, word));
    _notify();
    return null;
  }

  String? lookupCommandBlock(String text) => _chat.lookupCommandBlock(text);

  /// Why a send would be dropped right now (see ChatService), or null.
  String? get sendBusyReason => _chat.sendBusyReason;

  /// Why a message cannot be sent now (the speed test has the engine), as
  /// the desktop's composer is told; null when it can.
  String? sendRefusal(String text, {bool withImage = false}) =>
      _chat.sendRefusal(text, withImage: withImage);

  void continueGeneration() {
    withoutCity96Ask(_chat.continueGeneration);
    _notify();
  }

  // ── History: swipe, edit/delete, Needs redo, images, lorebook ─────────
  Map<String, dynamic> variants(int messageIndex) =>
      _history.variants(messageIndex);

  Future<void> selectVariant(int messageIndex, int variantIndex) =>
      _history.selectVariant(messageIndex, variantIndex);

  void impersonate(String prefix) => _history.impersonate(prefix);

  Future<bool> reprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) => _history.reprocessNeeds(index, critique, onlyNeeds: onlyNeeds);

  Future<FeelingsRescore> reprocessFeelings(int index) =>
      _history.reprocessFeelings(index);

  Future<bool> revertNeedsReprocess(int index) =>
      _history.revertNeedsReprocess(index);

  void swipe(int messageIndex, int direction, {String? critique}) =>
      _history.swipe(messageIndex, direction, critique: critique);

  void edit(int index, String text) => _history.edit(index, text);

  void delete(int index) => _history.delete(index);

  void resolveImageReview(String? prompt) =>
      _history.resolveImageReview(prompt);

  Future<String?> craftStudioPrompt(String subject, String instruction) =>
      _history.craftStudioPrompt(subject, instruction);

  Future<bool> insertImage(String filename, {String prompt = ''}) =>
      _history.insertImage(filename, prompt: prompt);

  void setAuthorNote(String note, {int? strength}) =>
      _history.setAuthorNote(note, strength: strength);

  Map<String, dynamic> chatLorebookRows() => _history.chatLorebookRows();

  Future<bool> setChatLorebook(dynamic rowsJson) =>
      _history.setChatLorebook(rowsJson);

  Future<bool> setThemeOverrides(Map<String, dynamic> json) =>
      _history.setThemeOverrides(json);

  List<String> lorePreview(String draft) => _history.lorePreview(draft);

  // ── Per-chat prompt source (desktop Chat Settings + new-chat picker) ────
  /// The new-chat picker's answer; a null [preset] is a dismiss. False when
  /// no 1:1 chat is open.
  Future<bool> answerPromptPicker({
    String? preset,
    bool remember = false,
    bool askEveryChat = false,
  }) async {
    if (_chat.activeGroup != null || _chat.activeCharacter == null) {
      return false;
    }
    await _chat.applyPromptSourceChoice(
      preset: preset,
      remember: remember,
      askEveryChat: askEveryChat,
    );
    return true;
  }

  Future<bool> setPromptSource({String? source, bool? amendments}) =>
      _chat.setPromptSource(source: source, amendments: amendments);

  // ── Personas ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> personas() => _personaOps.personas();

  Future<bool> setPersona(String id) => _personaOps.setPersona(id);

  Future<bool> setChatPersona(String id) => _personaOps.setChatPersona(id);

  Map<String, dynamic>? personaDetail(String id) =>
      _personaOps.personaDetail(id);

  Future<bool> createPersona(Map<String, dynamic> f) =>
      _personaOps.createPersona(f);

  Future<bool> updatePersona(String id, Map<String, dynamic> f) =>
      _personaOps.updatePersona(id, f);

  Future<bool> deletePersona(String id) => _personaOps.deletePersona(id);

  // ── Sessions ────────────────────────────────────────────────────────────
  /// All saved conversations. See [ChatSessionFacade.list].
  Future<List<Map<String, dynamic>>> sessions({
    String? characterId,
    String? groupId,
  }) => _sessions.list(characterId: characterId, groupId: groupId);

  /// New / load / delete. See [ChatSessionFacade.apply].
  Future<String?> session({
    String? action,
    String? sessionId,
    bool startReplacement = true,
  }) => _sessions.apply(
    action: action,
    sessionId: sessionId,
    startReplacement: startReplacement,
  );

  /// Fork at [messageIndex]. See [ChatSessionFacade.fork].
  Future<String?> fork(int messageIndex) => _sessions.fork(messageIndex);

  String? get currentSessionId => _chat.currentSessionId;

  void _notify() => _hub?.broadcastChatUpdate();
}
