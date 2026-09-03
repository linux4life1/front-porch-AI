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
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/facade/chat_session_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';

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

  /// Context Budget payload (desktop ContextViewerDialog parity): per-section
  /// token estimate + the REAL text each section contributed to the last
  /// assembled prompt. Additive endpoint — old clients simply never call it.
  Map<String, dynamic> contextBudget() {
    final texts = _chat.lastPromptSections;
    return {
      'contextLimit': _chat.contextSize,
      'source': _chat.promptBudgetSource.name,
      'assembledAt': _chat.promptBudgetAssembledAt?.toIso8601String(),
      'sections': [
        for (final e in _chat.lastPromptBudget.entries)
          {'label': e.key, 'tokens': e.value, 'text': texts[e.key] ?? ''},
      ],
    };
  }

  /// Rebuild a live estimate from the open chat (no model call).
  Future<Map<String, dynamic>> refreshContextBudget() async {
    await _chat.estimateContextBudgetNow();
    return contextBudget();
  }

  /// Full chat state payload (matches legacy `/api/chat/state`).
  Map<String, dynamic> state() {
    final activeChar = _chat.activeCharacter;
    final messages = _chat.messages.asMap().entries.map((e) {
      final m = e.value;
      final md = m.activeMetadata;
      final chips = _messageChips(md);
      // Generated-image messages (from /image or the Studio's "Send to chat")
      // and user-attached photos: expose the basename so the client renders
      // it via the existing GET /api/image/saved/<name> endpoint (both live
      // in the same images dir — desktop bubble parity).
      String? imageName;
      String? imagePrompt;
      if (md != null &&
          (md['is_generated_image'] == true || md['is_user_image'] == true)) {
        final ip = md['image_path'];
        if (ip is String) imageName = p.basename(ip);
        final pr = md['image_prompt'];
        if (pr is String && pr.isNotEmpty) imagePrompt = pr;
      }
      // Living Time §1 dream narration flag — additive; older bundles render
      // the dream as a plain message (same info, no special chrome).
      final bool? isDream = md?['is_dream'] == true ? true : null;
      return {
        'index': e.key,
        'sender': m.sender,
        'text': m.displayText,
        'isUser': m.isUser,
        'isDream': ?isDream,
        'hasThinking': m.hasThinking,
        'thinkingContent': m.thinkingContent,
        'thinkingDurationMs': m.thinkingDurationMs,
        'swipeCount': m.swipes.length,
        'swipeIndex': m.swipeIndex,
        'characterId': m.characterId,
        'chips': ?chips,
        'image': ?imageName,
        'imagePrompt': ?imagePrompt,
      };
    }).toList();

    final lorebook = <Map<String, dynamic>>[];
    // Post-group-filter truth: what actually injects this turn (an
    // inclusion-group loser stays isTriggered but must not read as active
    // in the web UI either — same source the desktop sidebar dots use).
    final injectedLore = _chat.currentlyActiveLoreEntries();
    final chatLen = _chat.messages.length;
    void addEntries(Iterable<dynamic> entries, String prefix) {
      for (final entry in entries) {
        if (!entry.enabled) continue;
        lorebook.add({
          'key': entry.key,
          'name': prefix.isEmpty
              ? entry.displayName
              : '$prefix: ${entry.displayName}',
          'isTriggered': injectedLore.contains(entry) && !entry.constant,
          'constant': entry.constant,
          'remainingDepth': entry.remainingDepth,
          // ST timed effects — the web timer pills (desktop sidebar parity).
          'stickyLeft': _chat.loreTimedEffects.stickyRemaining(entry, chatLen),
          'cooldownLeft': _chat.loreTimedEffects.cooldownRemaining(
            entry,
            chatLen,
          ),
        });
      }
    }

    // Chat-scoped book first (matches its scan priority), then char/members.
    addEntries(_chat.chatLorebook.entries, 'This chat');
    if (activeChar?.lorebook != null) {
      addEntries(activeChar!.lorebook!.entries, '');
    }
    if (_chat.isGroupMode) {
      for (final ch in _chat.groupCharacters) {
        if (ch.lorebook != null) addEntries(ch.lorebook!.entries, ch.name);
      }
    }

    return {
      'character': activeChar != null
          ? {'name': activeChar.name, 'id': activeChar.dbId}
          : null,
      // Title for the unified header: group name in a group, else the host name
      // (activeCharacter is null in a group, so the client can't rely on it).
      'chatTitle': _chat.activeGroup?.name ?? activeChar?.name,
      'sessionId': _chat.currentSessionId,
      'sessionName': _chat.sessionName,
      'messages': messages,
      'isGenerating': _chat.isGenerating || _chat.isImporting,
      // Additive (mixed-fleet safe): older web clients ignore it; newer ones
      // can distinguish "streaming tokens" from "still settling".
      'isSettlingTurn': _chat.isSettlingTurn,
      'isSendWaitingOnSettle': _chat.isSendWaitingOnSettle,
      // Overlay while setActiveCharacter/Group hydrates (navigate-first open).
      'isLoadingSession': _chat.isLoadingSession,
      'isBackfillingHistory': _chat.isBackfillingHistory,
      'hasOlderHistory': _chat.hasOlderHistory,
      // Processing-overlay state (mirrors the desktop Realism + Objective engine
      // overlays). The WS pushes a live `processing` event during eval; these
      // fields let a client that connects mid-eval render the overlay too.
      'isEvaluatingRealism': _chat.isEvaluatingRealism,
      'isCheckingCompletion': _chat.isCheckingCompletion,
      'isProcessingGreeting': _chat.isProcessingGreeting,
      'isVerifyingRealism': _chat.isVerifyingRealism,
      'realismEvalText': _chat.realismEvalStreamTextClean,
      'isGroupMode': _chat.isGroupMode,
      'groupId': _chat.activeGroup?.id,
      'groupMembers': _chat.isGroupMode
          ? _chat.groupCharacters
                .map(
                  (c) => {
                    'name': c.name,
                    'charId': c.imagePath != null
                        ? p.basenameWithoutExtension(c.imagePath!)
                        : c.name
                              .replaceAll(RegExp(r'[^\w\s]'), '')
                              .replaceAll(' ', '_'),
                    'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
                    'dbId': c.dbId,
                  },
                )
                .toList()
          : null,
      'tokensPerSecond': _chat.tokensPerSecond,
      'tokensGenerated': _chat.tokensGenerated,
      'authorNote': _chat.authorNote,
      'authorNoteDepth': _chat.authorNoteStrength,
      'summary': _chat.summary,
      'summaryLastIndex': _chat.summaryLastIndex,
      'summaryPaused': _chat.summaryPaused,
      'isSummaryGenerating': _chat.isSummaryGenerating,
      'greetingIndex': _chat.greetingIndex,
      'totalGreetings': () {
        final n = _chat.openingAllGreetings.length;
        return n < 1 ? 1 : n;
      }(),
      'userPersonaName': _personas?.persona.name ?? 'User',
      'lorebook': lorebook,
      // Living Worlds — places attached to this session (ids).
      'chatWorldIds': _chat.chatWorldIds,
      // Lore token meter (desktop sidebar parity): last generation's lore
      // share of the budget + anything dropped for space. Additive fields.
      'loreTokens': _chat.lastLoreTokens,
      'loreBudget': _chat.lastLoreBudget,
      'loreOverflow': _chat.lastLoreOverflow,
      'realism': _realism.snapshot(),
      // Active expression label (mood) so the web client can cache-bust the
      // expression portrait and only refetch when the mood actually changes.
      // Read-only — no reclassification here, so 1:1/group parity is unaffected.
      'expressionLabel': _chat.currentExpressionLabel,
      // Living Time §2 welcome-back banner — additive nullable; the shared
      // ChatService gate mirrors desktop (setting off / under threshold →
      // null). Coarse words only, computed locally from the chat's own
      // last-save time.
      'absencePhrase': _chat.absenceBannerPhrase,
      // Unified participant cast (host + scene guests in 1:1; members in group).
      // The single roster the unified chat UI iterates — no mode branching.
      'cast': _castJson(),
      // Transient scene-guest banner (creating/joining a guest) + a pending
      // "new character detected — add them?" offer, mirroring the desktop.
      'guestActivity': {
        'status': _chat.guestActivityStatus,
        'isError': _chat.guestActivityIsError,
        'busy': _chat.isGuestBusy,
      },
      'pendingDetection': _chat.pendingGuestDetection?.name,
      // Chance Time (chaos) park state. While `pending` is true the engine is
      // frozen waiting for the user to accept their fate — the web reveal modal
      // reads this on (re)connect (a phone that slept through the live
      // `chance_time` WS event still recovers). `event` is pre-resolved
      // ({{char}} substituted); the desktop shows its own spinning wheel.
      'chanceTime': {
        'pending': _chat.isAwaitingChanceTime,
        'event': ?_chat.webChanceTimeDisplay,
      },
      // Crafted /image prompt awaiting review (review setting on). The client
      // shows an edit modal and resolves via POST /api/chat/image-review.
      'imagePromptReview': ?_chat.pendingImagePromptReview,
      // Tool-calling verdict for the current backend+model (desktop sidebar
      // pill parity). Retest via POST /api/chat/tool-test. Additive field.
      'toolSupport': _chat.toolSupportJson,
      // Per-chat theme overrides (preset + font/color/background/border).
      'themeOverrides': _chat.sessionThemeOverrides.toJson(),
      // LLM backend connection (not a one-off request). Additive; older
      // PWAs ignore it and keep the normal composer placeholder.
      'llmReady': _llm?.activeService.isReady ?? true,
    };
  }

  Map<String, dynamic> variants(int messageIndex) =>
      _chat.variantPickerPayload(messageIndex);

  Future<void> selectVariant(int messageIndex, int variantIndex) async {
    await _chat.selectVariant(messageIndex, variantIndex);
    _notify();
  }

  /// Re-probe the current backend+model's tool-calling support (the web
  /// pill's tap-to-retest). Returns the fresh verdict.
  Future<Map<String, dynamic>> testToolCalling() async {
    await _chat.testToolCalling();
    return _chat.toolSupportJson;
  }

  /// The unified cast as JSON. Each entry carries enough to render a roster
  /// (avatar, role, emotion, next-up) and to scope the sidebar via [id]
  /// (stableGroupId). Avatars resolve to the character endpoint for host/guests
  /// and the group-member endpoint for members.
  List<Map<String, dynamic>> _castJson() {
    final groupId = _chat.activeGroup?.id;
    final nextDbId = _chat.nextCharacter?.dbId;
    final isGroup = _chat.isGroupMode;
    return _chat.cast.map((p) {
      final card = p.card;
      final avatarUrl = (isGroup && groupId != null)
          ? '/api/groups/$groupId/members/${card.dbId}/avatar'
          : '/api/characters/${card.dbId}/avatar';
      return {
        'id': p.id,
        'dbId': card.dbId,
        'name': p.name,
        'isHost': p.isHost,
        'isLite': p.isLite,
        'realismEnabled': p.realismEnabled,
        'emotion': !p.realismEnabled
            ? null
            : (isGroup
                  ? _chat.getEmotionForGroupCharacter(card)
                  : _chat.characterEmotion),
        'isNext': card.dbId != null && card.dbId == nextDbId,
        'hasAvatar': card.imagePath != null && card.imagePath!.isNotEmpty,
        'avatarUrl': avatarUrl,
      };
    }).toList();
  }

  /// Realism for a single cast participant (focus-scoped sidebar). Delegates to
  /// the [ChatRealismRead] leaf, which co-locates the host snapshot and the
  /// per-member branch (the 1:1-vs-group parity pair).
  Map<String, dynamic>? participantRealism(String participantId) =>
      _realism.participantRealism(participantId);

  /// Extract the per-message Realism chip deltas from a message's active-swipe
  /// metadata (the same keys the desktop bubble reads), omitting zeros/empties.
  Map<String, dynamic>? _messageChips(Map<String, dynamic>? md) {
    if (md == null) return null;
    final out = <String, dynamic>{};
    for (final entry in const {
      'bond_delta': 'bondDelta',
      'trust_delta': 'trustDelta',
      'arousal_delta': 'arousalDelta',
    }.entries) {
      final v = md[entry.key];
      if (v is int && v != 0) out[entry.value] = v;
    }
    for (final entry in const {
      'emotion_label': 'emotionLabel',
      'bond_reason': 'bondReason',
      'trust_reason': 'trustReason',
      'time_skip_to': 'timeSkipTo',
      'chance_time_event': 'chanceTimeEvent',
    }.entries) {
      final v = md[entry.key];
      if (v is String && v.isNotEmpty) out[entry.value] = v;
    }
    final needs = md['needs_deltas'];
    if (needs is Map) {
      final nz = <String, dynamic>{};
      needs.forEach((k, v) {
        // NeedsSimulation.computeNeedsDeltasWithReasons stores {delta, reason}
        // per need; tolerate a plain int too. Carry BOTH the signed delta and
        // the reason so the web chip can show the same hover explanation the
        // desktop bubble does. (Map-not-int is why needs chips never rendered
        // on the web before — see the chip parser fix.)
        final delta = v is int
            ? v
            : (v is Map && v['delta'] is int ? v['delta'] as int : 0);
        if (delta == 0) return;
        final reason = (v is Map && v['reason'] is String)
            ? (v['reason'] as String)
            : '';
        nz[k.toString()] = {'delta': delta, 'reason': reason};
      });
      if (nz.isNotEmpty) out['needsDeltas'] = nz;
    }
    // Director-redo affordances (mirrors message_bubble.dart): the message can be
    // reprocessed when it carries a needs snapshot, and reverted when a
    // pre-reprocess stash exists. The client additionally gates "reprocess" on
    // this being the last, non-generating message (it already knows both).
    final rs = md['realism_state'];
    if (rs is Map && rs['needs'] != null) out['needsReprocessable'] = true;
    if (md['needs_deltas_pre_reprocess'] is Map) out['needsRevertable'] = true;
    return out.isEmpty ? null : out;
  }

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

  void send(String text) {
    _chat.sendMessage(text);
    _notify();
  }

  void stop() {
    _chat.stopGeneration();
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

  /// Escape hatch for the realism-processing overlay's "Cancel Realism" button —
  /// aborts an in-flight Realism eval (mirrors the desktop overlay action).
  void cancelRealismEval() {
    _chat.cancelRealismEval();
    _notify();
  }

  void regenerate() {
    _chat.regenerateLastMessage();
    _notify();
  }

  void continueGeneration() {
    _chat.continueGeneration();
    _notify();
  }

  /// AI writes the user's next line into the composer (desktop wand parity).
  /// Tokens ride a dedicated `impersonate` WS event — never the `token`
  /// bubble stream.
  void impersonate(String prefix) {
    unawaited(
      _chat
          .impersonateUser(
            prefix: prefix,
            onToken: (acc) => _hub?.broadcastImpersonate(acc),
          )
          .whenComplete(() {
            _hub?.broadcastImpersonateDone();
            _notify();
          }),
    );
    _notify();
  }

  /// Director redo: re-evaluate a message's Needs deltas using the user's
  /// written [critique]. Awaited (it runs LLM evals) so the route can report the
  /// outcome; the new deltas + a pre-reprocess stash land in the message's
  /// metadata, which the next state fetch surfaces as chips. Reuses the existing
  /// ChatService flow — no parallel logic.
  /// [onlyNeeds] scopes the pass to those needs; empty re-evaluates all of
  /// them. Additive on the wire — an older PWA that omits it keeps the
  /// all-needs behaviour it has always had.
  Future<bool> reprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) async {
    final ok = await _chat.manualReprocessNeeds(
      index,
      critique,
      onlyNeeds: onlyNeeds,
    );
    _notify();
    return ok;
  }

  /// Restore a message's Needs deltas + live state from the pre-reprocess stash.
  Future<bool> revertNeedsReprocess(int index) async {
    final ok = await _chat.revertNeedsReprocess(index);
    _notify();
    return ok;
  }

  void swipe(int messageIndex, int direction) {
    _chat.swipeMessage(messageIndex, direction);
    _notify();
  }

  void edit(int index, String text) {
    _chat.editMessage(index, text);
    _notify();
  }

  void delete(int index) {
    _chat.deleteMessage(index);
    _notify();
  }

  /// Attach a generated image (saved under `KoboldManager/images/`) to the
  /// conversation as its own image message — the SAME path the desktop's
  /// /image command and the Image Studio's "Send to chat" use
  /// (ChatServiceImages.addGeneratedImageMessage), so it renders identically
  /// on both surfaces. Replaces the old markdown-append-to-last-message hack,
  /// which never rendered on desktop (relative URLs aren't matched by the
  /// markdown-image regex) and mutated an unrelated message.
  /// Resolve a parked /image prompt review from the web modal: the (possibly
  /// edited) prompt to generate with, or null to cancel. No-op when nothing
  /// is pending (e.g. the desktop dialog resolved it first).
  void resolveImageReview(String? prompt) {
    _chat.resolveImagePromptReview(prompt);
    _notify();
  }

  Future<bool> insertImage(String filename, {String prompt = ''}) async {
    final file = _resolveSavedImage?.call(filename.trim());
    if (file == null) return false;
    await _chat.addGeneratedImageMessage(file.path, prompt);
    _notify();
    return true;
  }

  void setAuthorNote(String note, {int? strength}) {
    _chat.setAuthorNote(note, strength: strength);
    _notify();
  }

  /// All user personas for the web persona surfaces.
  ///
  /// Two flags, because there are two distinct answers: `default` is who a NEW
  /// chat starts as (Settings), `active` is who the CURRENT chat is speaking as
  /// (the in-chat switcher). `active` is kept for older PWA builds that only
  /// know that key — additive-only, per the API contract.
  List<Map<String, dynamic>> personas() {
    final svc = _personas;
    if (svc == null) return const [];
    final activeId = svc.persona.id;
    final defaultId = svc.defaultPersonaId;
    return svc.personas
        .map(
          (p) => {
            'id': p.id,
            'label': p.displayLabel,
            'name': p.name,
            'active': p.id == activeId,
            'default': p.id == defaultId,
          },
        )
        .toList();
  }

  /// Change which persona NEW chats start as (Settings → Personas). Leaves the
  /// open chat alone. Returns false if personas aren't wired.
  Future<bool> setPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setDefaultPersona(id);
    _notify();
    return true;
  }

  /// Speak as [id] in the CURRENT chat, and bind the session to it — the web
  /// counterpart of the desktop composer's persona switcher. Saves immediately
  /// so the binding survives a reload even if the user says nothing else.
  Future<bool> setChatPersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.setActivePersona(id);
    await _chat.persistSessionPersona();
    _notify();
    return true;
  }

  /// Full persona detail for the editor (text + name/title), or null if absent.
  Map<String, dynamic>? personaDetail(String id) {
    final svc = _personas;
    if (svc == null) return null;
    for (final p in svc.personas) {
      if (p.id == id) {
        return {
          'id': p.id,
          'title': p.title,
          'name': p.name,
          'persona': p.persona,
          'birthday': p.birthday,
        };
      }
    }
    return null;
  }

  /// Create a new persona (and make it active, matching the desktop). Returns
  /// false if personas aren't wired.
  Future<bool> createPersona(Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    await svc.createPersona(
      f['title']?.toString() ?? '',
      f['name']?.toString() ?? 'User',
      f['persona']?.toString() ?? '',
      null,
      birthday: f['birthday']?.toString() ?? '',
    );
    _notify();
    return true;
  }

  /// Edit an existing persona's text fields (only provided keys change).
  Future<bool> updatePersona(String id, Map<String, dynamic> f) async {
    final svc = _personas;
    if (svc == null) return false;
    UserPersona? existing;
    for (final p in svc.personas) {
      if (p.id == id) {
        existing = p;
        break;
      }
    }
    if (existing == null) return false;
    await svc.updatePersona(
      existing.copyWith(
        title: f.containsKey('title') ? f['title']?.toString() : null,
        name: f.containsKey('name') ? f['name']?.toString() : null,
        persona: f.containsKey('persona') ? f['persona']?.toString() : null,
        birthday: f.containsKey('birthday') ? f['birthday']?.toString() : null,
      ),
    );
    _notify();
    return true;
  }

  /// Delete a persona. The service refuses to delete the last one (throws),
  /// which we surface as false. Returns false if personas aren't wired.
  Future<bool> deletePersona(String id) async {
    final svc = _personas;
    if (svc == null) return false;
    try {
      await svc.deletePersona(id);
    } catch (_) {
      return false;
    }
    _notify();
    return true;
  }

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

  /// The chat-scoped lorebook as web editor rows (full-fidelity via `ext`).
  Map<String, dynamic> chatLorebookRows() => {
    'entries': lorebookEntriesToJson(_chat.chatLorebook),
  };

  /// Replace the chat-scoped lorebook from web editor rows. An empty/absent
  /// list clears it. Returns false when no session is active.
  Future<bool> setChatLorebook(dynamic rowsJson) async {
    if (_chat.currentSessionId == null) return false;
    final built = buildLorebookFromJson(rowsJson);
    _chat.chatLorebook.entries
      ..clear()
      ..addAll(built?.entries ?? const []);
    await _chat.commitChatLorebookEdit();
    _notify();
    return true;
  }

  /// Save per-chat theme overrides from the web UI.
  Future<bool> setThemeOverrides(Map<String, dynamic> json) async {
    if (_chat.currentSessionId == null) return false;
    _chat.sessionThemeOverrides = ChatThemeOverrides.fromJson(json);
    _notify();
    return true;
  }

  /// Mutation-free "would trigger next" preview for a composer draft —
  /// display names of idle entries the draft would wake up.
  List<String> lorePreview(String draft) => [
    for (final e in _chat.previewLoreTriggers(draft)) e.displayName,
  ];

  void _notify() => _hub?.broadcastChatUpdate();
}
