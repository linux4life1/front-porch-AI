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

part 'chat_facade_history.dart';

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
    final search = md['search_receipt'];
    if (search is Map) {
      final q = (search['query'] as String?)?.trim() ?? '';
      if (q.isNotEmpty) {
        out['searchQuery'] = q;
        out['searchOk'] = search['ok'] == true;
      }
    }
    final toolReceipt = md['tool_receipt'];
    if (toolReceipt is Map) {
      final tool = (toolReceipt['tool'] as String?)?.trim() ?? '';
      if (tool.isNotEmpty) {
        out['toolName'] = tool;
        out['toolOk'] = toolReceipt['ok'] == true;
        // Older phone bundles read mcpTool; keep the keys until they age out.
        out['mcpTool'] = tool;
        out['mcpOk'] = toolReceipt['ok'] == true;
      }
    }
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

  void regenerate({String? critique}) {
    _chat.regenerateLastMessage(critique: critique);
    _notify();
  }

  void continueGeneration() {
    _chat.continueGeneration();
    _notify();
  }

  void _notify() => _hub?.broadcastChatUpdate();
}
