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

part of 'chat_facade.dart';

/// Full `/api/chat/state` payload. Send/load and history stay on [ChatFacade].
extension ChatFacadeState on ChatFacade {
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
}
