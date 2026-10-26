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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/director/director.dart'
    show kDirectorQuickBeats;
import 'package:front_porch_ai/services/chat/scene/scene_resolver.dart';
import 'package:front_porch_ai/services/web/facade/chat/chat_message_chips.dart';
import 'package:front_porch_ai/services/web/facade/chat_realism_read.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

/// Builds the full `/api/chat/state` payload from the live chat.
class ChatStateSnapshot {
  ChatStateSnapshot(
    this._chat,
    this._characters,
    this._personas,
    this._hub,
    this._llm,
    this._realism,
  );

  final ChatService _chat;
  final CharacterRepository _characters;
  final StreamHub? _hub;
  final UserPersonaService? _personas;

  /// Null in tests that construct a facade without a provider — treated as
  /// ready so they do not inherit a "No API connection" hint.
  final LLMProvider? _llm;
  final ChatRealismRead _realism;

  /// Full chat state payload (matches legacy `/api/chat/state`).
  Map<String, dynamic> build() {
    final activeChar = _chat.activeCharacter;
    final base = _chat.historyBasePosition;
    final messages = _chat.messages.asMap().entries.map((e) {
      final m = e.value;
      final md = m.activeMetadata;
      final chips = webMessageChips(_chat, md, e.key);
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
        // Stable across prepend (same Dart object). Index shifts and
        // remounts every row — that resets the web scrollbar thumb.
        'rowKey': identityHashCode(m),
        // Place in the whole chat (0-based) while older rows still load;
        // `index` stays the action address.
        'position': base + e.key,
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
        if (m.isDirectorNarration) 'isNarration': true,
        if (!m.isUser && md?[kReplyContextKey] is Map) 'hasContext': true,
        if (!m.isUser && md?[kTokenAltsKey] is List) 'hasTokenAlts': true,
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
      addEntries(_chat.groupLorebookEntries, 'Group');
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
      // Additive: the group's stored lorebook could not be read (the
      // desktop sidebar's note).
      'groupLorebookUnreadable': _chat.groupLorebookUnreadable,
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
      // Director Mode: the user off stage, auto-chat, and whether a member
      // may leave (not the second-to-last while directing). Additive.
      'director': {
        'directing': _chat.observerMode,
        'autoPlay': _chat.autoPlayActive,
        // Asked only while directing, the one time the strip shows it.
        'delaySeconds': _chat.observerMode ? _chat.savedDirectorDelay : null,
        'canRemoveMember': !_chat.isGroupMode || _chat.canRemoveCastMember,
        // The director's tools, served so the web shows what desktop shows.
        'beats': [for (final b in kDirectorQuickBeats) b.toJson()],
        // Who a cue can call on: the desktop panel's own list.
        'members': [for (final c in _chat.groupCharacters) c.name],
        'goal': _chat.directorGoal,
        'whispers': [
          for (final w in _chat.directorWhisperRows)
            {'id': w.id, 'name': w.name, 'text': w.text},
        ],
        'turnBudget': _chat.savedDirectorTurnBudget,
        'turnsLeft': _chat.autoChatTurnsLeft,
        // Paused with turns left: the strip offers Resume. Additive.
        'autoPlayPaused': _chat.autoPlayPaused,
        // The narrator's beat counts as a running turn.
        'narrating': _chat.isNarrating,
      },
      // The open /exit UNDO (a guest, a member, or the user stepping out to
      // direct) until a send or a chat switch closes it. Additive nullable.
      'exitUndo': _chat.exitUndoName == null
          ? null
          : {'name': _chat.exitUndoName, 'isUser': _chat.exitUndoIsUserStep},
      // A reply stopped from the Realism overlay. Stays until the chat moves
      // on (a send, Try again, another chat) or it is dismissed. Additive.
      'stoppedReply': _chat.stoppedReplyNotice == null
          ? null
          : {
              'notice': _chat.stoppedReplyNotice,
              'canRetry': _chat.canRetryStoppedReply,
            },
      'pendingDetection': _chat.pendingGuestDetection?.name,
      // Slice 6 (additive): a suggested scene move awaiting the author.
      // The PWA shows the same dialog the desktop does; answering it is
      // one POST. Absent key on an older desktop relay = no offer.
      // Slice 7 (additive): a proposed NAMED new place awaiting the tap.
      'pendingMint': _chat.pendingPlaceMint == null
          ? null
          : {
              'name': _chat.pendingPlaceMint!.name,
              'descriptor': _chat.pendingPlaceMint!.descriptor,
              'settingName': _chat.pendingPlaceMint!.settingName,
            },
      'pendingPlaceMove': _chat.pendingPlaceMove == null
          ? null
          : {
              'id': _chat.pendingPlaceMove!.id,
              'name': _chat.pendingPlaceMove!.name,
            },
      'pendingPicker': _chat.pendingGuestPickerFilter == null
          ? null
          : {
              'filter': _chat.pendingGuestPickerFilter,
              'full': _chat.pendingGuestPickerFull,
            },
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
      // The Ambient Stage's scene: the story's weather as the colour strings
      // the PWA paints behind the bubbles, for both brightnesses so the PWA
      // paints its own mode (docs/design/ambient-stage.md). Null when
      // Ambient scene is Off or the chat has no weather. Additive.
      'scene': sceneWireFor(_chat),
      // Per-chat system prompt source (1:1 only) and, while a new chat
      // waits on it, the picker's prompts. Additive; omitted in groups.
      'promptSource': ?_chat.promptSourceJson,
      // LLM backend connection (not a one-off request). Additive; older
      // PWAs ignore it and keep the normal composer placeholder. Local
      // GGUF-ready is ignored so mouth/worker swaps do not flash the box.
      'llmReady': _llm?.composerConnectionReady ?? true,
      // Why the app's start of KoboldCpp was refused, for the composer's
      // placeholder in place of "No API connection". Additive; omitted when
      // there is nothing to say.
      'llmHint': ?_llm?.composerConnectionHint,
      // Which named lookups the regenerate dialog may offer. Web is omitted
      // on the client when false. Wiki stays visible but disabled.
      'lookupSources': {
        'web': _chat.webSearchEnabled,
        'wiki': _chat.wikiLookupAvailable,
      },
    };
  }

  /// The unified cast as JSON. Each entry carries enough to render a roster
  /// (avatar, role, emotion, next-up) and to scope the sidebar via [id]
  /// ([groupMemberStoreId] in groups). Avatars resolve to the character endpoint for host/guests
  /// and the group-member endpoint for members.
  List<Map<String, dynamic>> _castJson() {
    final groupId = _chat.activeGroup?.id;
    final nextDbId = _chat.nextCharacter?.dbId;
    final isGroup = _chat.isGroupMode;
    final placeholders = _placeholderCastIds(isGroup);
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
        // Group members only: withYou / away / atWork (additive).
        'presence': isGroup ? _chat.groupMemberPresence(p.id)?.name : null,
        'hasAvatar': card.imagePath != null && card.imagePath!.isNotEmpty,
        'avatarUrl': avatarUrl,
        // The picture is only the flat no-portrait colour: the header and
        // side portrait skip it (additive field).
        'placeholderPortrait': placeholders.contains(p.id),
      };
    }).toList();
  }

  /// Cast ids whose avatar is the flat placeholder a character made without
  /// a portrait carries. The chat state is refetched constantly, so this
  /// never waits: it answers from the probe cache, counts an unknown picture
  /// as real, probes it in the background, and pushes one `chat_updated`
  /// when that finds a placeholder.
  Set<String> _placeholderCastIds(bool isGroup) {
    final ids = <String>{};
    final unknown = <Future<bool>>[];
    final epoch = _characters.coverEpoch;
    final library = isGroup ? const <String, CharacterCard>{} : _castLibrary();
    for (final p in _chat.cast) {
      final file = _castAvatarFile(p.card, isGroup, library);
      if (file == null) continue;
      final known = PlaceholderPortraitProbe.known(file, version: epoch);
      if (known == true) ids.add(p.id);
      if (known == null) {
        unknown.add(PlaceholderPortraitProbe.check(file, version: epoch));
      }
    }
    if (unknown.isNotEmpty) {
      Future.wait(unknown).then((found) {
        if (found.contains(true)) _hub?.broadcastChatUpdate();
      });
    }
    return ids;
  }

  /// The file the cast entry's `avatarUrl` serves: a group member's private
  /// copy, else the library card's (★-aware) cover.
  File? _castAvatarFile(
    CharacterCard card,
    bool isGroup,
    Map<String, CharacterCard> library,
  ) {
    if (isGroup) {
      final path = card.imagePath;
      return path == null || path.isEmpty ? null : File(path);
    }
    return _characters.coverImageFileFor(library[card.dbId] ?? card);
  }

  /// The cast's library cards by dbId, from one pass over the library per
  /// state build (stopping once every cast member is found).
  Map<String, CharacterCard> _castLibrary() {
    final wanted = {
      for (final p in _chat.cast)
        if (p.card.dbId != null) p.card.dbId!,
    };
    final found = <String, CharacterCard>{};
    if (wanted.isEmpty) return found;
    for (final c in _characters.characters) {
      final id = c.dbId;
      if (id != null && wanted.contains(id)) {
        found[id] = c;
        if (found.length == wanted.length) break;
      }
    }
    return found;
  }
}
