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
//
// Sidebar shell for ChatPage: the right-sidebar frame and its section order,
// the participant roster, and the Director controls; plus the transcript
// anchors the sidebar's journal receipts jump to. The portrait and Main
// Settings blocks live in chat_page.sidebar_widgets.dart.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/pages/chat_page.scene_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.session_dialogs.dart';
import 'package:front_porch_ai/ui/pages/chat_page.sidebar_widgets.dart';
import 'package:front_porch_ai/ui/pages/chat_page.speakers.dart';

/// Opens the character editor for a card; the env-driven open also scrolls
/// the Relationship block into view.
typedef EditCharacterLauncher =
    Future<void> Function(
      CharacterCard character, {
      bool ensureRelationshipVisible,
    });

/// The chat page's per-message bubble keys and the tap-to-jump flash.
///
/// The keys used to be `GlobalObjectKey(msg)` — whose identity is the
/// message alone — and a GlobalKey must be unique across the whole app. Two
/// ChatPage routes can be alive in the same frame (a push over a
/// not-yet-disposed page, or the frames of a route transition), and both
/// listen to the same ChatService, so a chat switch had BOTH pages building
/// bubbles for the same message objects: one duplicate-key crash per visible
/// message, then cascading tree corruption (maintainer repro, 2026-08-10).
/// Keys minted per page instance can never collide across pages; the jump
/// looks them up through [keyOf]. Identity map on purpose: message equality
/// is identity everywhere else (list diffing, jump targets, flash).
class ChatTranscriptAnchors {
  final Map<ChatMessage, GlobalKey> _bubbleKeys = HashMap.identity();

  // Prune marker: entries live until the session changes (or the page dies),
  // so a long-lived page can't accumulate every past chat's messages.
  String? _bubbleKeysSessionId;

  /// Journal receipts tap-to-jump: the just-landed-on bubble, briefly tinted.
  ChatMessage? jumpFlash;

  /// Drop every key when [sessionId] is a new chat. Returns whether it was.
  bool syncSession(String? sessionId) {
    if (_bubbleKeysSessionId == sessionId) return false;
    _bubbleKeys.clear();
    _bubbleKeysSessionId = sessionId;
    return true;
  }

  /// This page's key for [m]'s bubble, minted on first build.
  GlobalKey keyFor(ChatMessage m) => _bubbleKeys.putIfAbsent(m, GlobalKey.new);

  /// The key of an already-built bubble, else null.
  GlobalKey? keyOf(ChatMessage m) => _bubbleKeys[m];

  /// Journal receipts tap-to-jump: seek the chat to the message at
  /// [position] (the stored absolute index), then flash the bubble so the
  /// eye finds it. The seek itself lives in message_jump.dart. [update] is
  /// the page's setState; [isMounted] its lifetime.
  Future<void> jumpTo(
    int position, {
    required List<ChatMessage> messages,
    required TranscriptWindow window,
    required ScrollController controller,
    required void Function(VoidCallback fn) update,
    required ValueGetter<bool> isMounted,
  }) async {
    if (position < 0 || position >= messages.length) return;
    final target = messages[position];
    window.revealAround(position, messages.length);
    update(() {});
    await WidgetsBinding.instance.endOfFrame;
    await jumpToMessage(
      controller: controller,
      messages: messages,
      target: target,
      builtStart: window.start,
      builtEnd: window.end,
      // This page's own keys. Null for a not-yet-built bubble — the seek
      // treats that as "keep paging"; the itemBuilder mints the key the
      // moment the bubble materializes.
      keyOf: keyOf,
    );
    if (!isMounted()) return;
    update(() => jumpFlash = target);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (isMounted() && identical(jumpFlash, target)) {
        update(() => jumpFlash = null);
      }
    });
  }
}

/// The chat's right sidebar for the focused cast member: portrait, Main
/// Settings, group controls, roster, then the scrolling section body.
class ChatRightSidebar extends StatelessWidget {
  const ChatRightSidebar({
    super.key,
    required this.chatService,
    required this.focusedParticipantId,
    required this.onFocusParticipant,
    required this.sidebarWidth,
    required this.resolveCharImage,
    required this.draft,
    required this.onJumpToMessage,
    required this.onEditCharacter,
    required this.onAvatarsChanged,
  });

  final ChatService chatService;

  /// The roster pick; null (or gone from the cast) = the first participant.
  final String? focusedParticipantId;
  final ValueChanged<String> onFocusParticipant;
  final double sidebarWidth;
  final File Function(String imagePath) resolveCharImage;

  /// The message box, for sections that read the draft.
  final TextEditingController draft;
  final ValueChanged<int> onJumpToMessage;
  final EditCharacterLauncher onEditCharacter;

  /// The focused card's avatar images were edited in place.
  final VoidCallback onAvatarsChanged;

  @override
  Widget build(BuildContext context) {
    final focused = focusedChatParticipant(chatService, focusedParticipantId);
    if (focused == null) return const SizedBox.shrink();
    final character = focused.card;
    final isGroup = chatService.isGroupMode;
    final cast = chatService.cast;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          left: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Column(
        children: [
          ChatSidebarPortrait(
            character: character,
            isGroup: isGroup,
            sidebarWidth: sidebarWidth,
            resolveCharImage: resolveCharImage,
          ),
          ChatSidebarMainSettings(
            chatService: chatService,
            character: character,
            isGroup: isGroup,
            onEditCharacter: (card) => onEditCharacter(card),
            onAvatarsChanged: onAvatarsChanged,
          ),

          // ── Group Settings (group only; sits directly under Main Settings,
          //    above the cast roster, so the whole-group controls are found
          //    before per-character ones) ──
          if (isGroup)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.borderOf(context).withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showGroupSettings(context, chatService),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Group Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(
                      color: AppColors.borderOf(context).withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ),

          // ── Participant roster (only when more than one speaker) ──
          if (cast.length > 1)
            _ParticipantRoster(
              chatService: chatService,
              cast: cast,
              focused: focused,
              resolveCharImage: resolveCharImage,
              onFocus: onFocusParticipant,
            ),

          // ── Director: step out to direct, or back in ──
          if (isGroup || cast.length > 1)
            Consumer<StorageService>(
              builder: (context, storage, _) {
                final delay = storage.ttsSettings.directorDelay;
                chatService.directorDelaySec = delay;
                return DirectorPanel(
                  directing: chatService.observerMode,
                  busy: chatService.isGenerating,
                  delaySeconds: delay,
                  onStepOut: () =>
                      unawaited(chatService.sendMessage('/director')),
                  onStepIn: () =>
                      unawaited(chatService.sendMessage('/director off')),
                  onDelayChanged: storage.ttsSettings.setDirectorDelay,
                  tools: DirectorTools(
                    memberNames: [
                      for (final c in chatService.groupCharacters) c.name,
                    ],
                    goal: chatService.directorGoal,
                    whispers: chatService.directorWhisperRows,
                    turnBudget: storage.ttsSettings.directorTurnBudget,
                    turnsLeft: chatService.autoPlayActive
                        ? chatService.autoChatTurnsLeft
                        : null,
                    busy: chatService.isGenerating,
                    onCue: (name) =>
                        unawaited(chatService.sendMessage('/speak $name')),
                    onBeat: (note) => unawaited(chatService.sendMessage(note)),
                    onGoal: (text) =>
                        unawaited(chatService.setDirectorGoal(text)),
                    onClearWhisper: (id) =>
                        unawaited(chatService.setDirectorWhisper(id, '')),
                    onTurnBudget: (n) =>
                        unawaited(storage.ttsSettings.setDirectorTurnBudget(n)),
                  ),
                );
              },
            ),

          Expanded(
            child: SidebarBody(
              chatService: chatService,
              focused: focused,
              onSpinRequested: () => showChanceTimeOverlay(context),
              onJumpToMessage: onJumpToMessage,
              resolveCharImage: resolveCharImage,
              draft: draft,
              onOpenEditFromEnv: () {
                unawaited(
                  onEditCharacter(character, ensureRelationshipVisible: true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal roster of all cast participants. Tapping one focuses its
/// per-character sidebar sections. Shown only when more than one speaker is
/// present (1:1 + guests, or a group). Soft guests show GUEST + Promote
/// here — this is the only Promote chrome. Character State may still
/// show a GUEST badge; it does not get a second button.
class _ParticipantRoster extends StatelessWidget {
  const _ParticipantRoster({
    required this.chatService,
    required this.cast,
    required this.focused,
    required this.resolveCharImage,
    required this.onFocus,
  });

  final ChatService chatService;
  final List<ChatParticipant> cast;
  final ChatParticipant focused;
  final File Function(String imagePath) resolveCharImage;
  final ValueChanged<String> onFocus;

  @override
  Widget build(BuildContext context) {
    final hasLite = cast.any((p) => p.isLite);
    return Container(
      height: hasLite ? 96 : 66,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.35),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = cast[i];
          final path = p.card.imagePath;
          final img = (path != null && path.isNotEmpty)
              ? resolveCharImage(path)
              : null;
          return CastRosterChip(
            name: p.name,
            color: groupCharacterColor(i),
            isFocused: p.id == focused.id,
            isLite: p.isLite,
            imageFile: img,
            promoteEnabled: !chatService.isGenerating,
            onFocus: () => onFocus(p.id),
            onPromote: p.isLite
                ? () {
                    if (chatService.isGroupMode) {
                      unawaited(chatService.promoteGuestToFull(p.card));
                    } else {
                      unawaited(chatService.joinFull(p.card));
                    }
                  }
                : null,
          );
        },
      ),
    );
  }
}
