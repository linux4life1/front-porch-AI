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
// ChatPage scene dialogs: Chance Time overlay, the /image prompt review, the
// Scene Guest detection/picker flow and exit undo, convert-to-group, and the
// Image Studio launcher.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';

import 'chat_page_scene_location_dialogs.dart';

/// The Chance Time wheel, over the chat.
void showChanceTimeOverlay(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ChanceTimeOverlay(),
  );
}

/// ChatService raises scene prompts as pending flags (the Chance-Time
/// pattern); this answers each one once, on the next frame, from the chat
/// page. The `_showing…` guards stop a popup stacking while it is open.
class ChatScenePrompts {
  ChatScenePrompts({required this.coverFor});

  final File? Function(ChatService chat, CharacterCard card) coverFor;

  bool _showingGuestDetection = false;
  bool _showingPlaceMove = false;
  bool _showingPlaceMint = false;
  bool _showingGuestPicker = false;
  bool _showingImageReview = false;
  bool _showingSkip = false;

  /// Handle one ChatService notification. [context] is the mounted chat
  /// page's; [onGuestAvatarReady] gets the image path of a guest whose
  /// background portrait just finished.
  void onChatChanged(
    BuildContext context,
    ChatService chat, {
    required ValueChanged<String> onGuestAvatarReady,
  }) {
    if (chat.chanceTimePendingTrigger) {
      chat.consumeChanceTimeTrigger();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showChanceTimeOverlay(context),
      );
    }
    // Scene Guest cast detection — same Chance-Time-style pending-flag pattern.
    if (chat.pendingGuestDetection != null && !_showingGuestDetection) {
      _showingGuestDetection = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showGuestDetectionDialog(context, chat),
      );
    }
    // Slice 6: the clock judge flagged an arrival — ask, never assume.
    if (chat.pendingPlaceMove != null && !_showingPlaceMove) {
      _showingPlaceMove = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showPlaceMoveDialog(context, chat),
      );
    }
    // Slice 7: the judge heard a NAMED new place — offer the mint.
    // The two locations asks never stack: a mint waits for the move
    // to be answered (the move flow re-checks when it returns).
    if (chat.pendingPlaceMove == null &&
        chat.pendingPlaceMint != null &&
        !_showingPlaceMint) {
      _showingPlaceMint = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showPlaceMintDialog(context, chat),
      );
    }
    // Scene Guest `/join` picker — same pending-flag pattern.
    if (chat.pendingGuestPickerFilter != null && !_showingGuestPicker) {
      _showingGuestPicker = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showGuestPickerDialog(context, chat),
      );
    }
    // /image prompt review — same pending-flag pattern (review setting on).
    if (chat.pendingImagePromptReview != null && !_showingImageReview) {
      _showingImageReview = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showImagePromptReviewDialog(context, chat),
      );
    }
    // "Did time pass?" — the send waits on it (#629).
    if (chat.pendingSkip != null && !_showingSkip) {
      _showingSkip = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showSkipConfirm(context, chat),
      );
    }
    // A guest's background portrait finished — the page evicts its stale
    // cached image so the new art replaces the initials avatar.
    final evictPath = chat.guestAvatarEvictPath;
    if (evictPath != null) {
      chat.consumeGuestAvatarEvict();
      onGuestAvatarReady(evictPath);
    }
    // A guest just /exit-ed — offer a brief UNDO (delete the departure message
    // + restore the guest with full context). Consume the offer so it shows once.
    final exitUndoName = chat.exitUndoOfferName;
    if (exitUndoName != null) {
      chat.consumeExitUndoOffer();
      final label = chat.exitUndoIsUserStep
          ? 'You stepped out to direct'
          : '$exitUndoName left the scene';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(label),
            duration: const Duration(seconds: 8),
            // Flutter's SnackBar.persist defaults to `action != null`, so an
            // action snackbar silently ignores its duration and stays forever
            // (the auto-dismiss timer fires but early-returns on persist). We
            // want it to disappear after 8s, so opt out explicitly.
            persist: false,
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => chat.undoLastExit(),
            ),
          ),
        );
      });
    }
  }

  Future<void> _showSkipConfirm(BuildContext context, ChatService chat) async {
    final question = chat.pendingSkip;
    if (question == null || !context.mounted) {
      _showingSkip = false;
      return;
    }
    final answer = await showSkipConfirmDialog(
      context,
      question: question,
      changes: chat,
      isLive: () => identical(chat.pendingSkip, question),
    );
    _showingSkip = false;
    if (identical(chat.pendingSkip, question)) {
      chat.answerSkip(answer);
    } else if (chat.pendingSkip != null && context.mounted) {
      // A newer question took this one's place while it closed.
      _showingSkip = true;
      await _showSkipConfirm(context, chat);
    }
  }

  Future<void> _showImagePromptReviewDialog(
    BuildContext context,
    ChatService chat,
  ) async {
    final prompt = chat.pendingImagePromptReview;
    if (prompt == null || !context.mounted) {
      _showingImageReview = false;
      return;
    }
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImagePromptReviewDialog(prompt: prompt),
    );
    _showingImageReview = false;
    chat.resolveImagePromptReview(result);
  }

  Future<void> _showPlaceMintDialog(
    BuildContext context,
    ChatService chat,
  ) async {
    try {
      await showPlaceMintFlow(context, chat);
    } finally {
      // The one-shot guard must release even if the flow throws, or a
      // second proposal this chat never gets a dialog (review #607
      // blocker class).
      _showingPlaceMint = false;
    }
  }

  Future<void> _showPlaceMoveDialog(
    BuildContext context,
    ChatService chat,
  ) async {
    try {
      await showPlaceMoveFlow(context, chat);
    } finally {
      _showingPlaceMove = false;
    }
    if (chat.pendingPlaceMint != null && !_showingPlaceMint) {
      _showingPlaceMint = true;
      await _showPlaceMintDialog(context, chat);
    }
  }

  Future<void> _showGuestDetectionDialog(
    BuildContext context,
    ChatService chat,
  ) async {
    final detected = chat.pendingGuestDetection;
    if (detected == null || !context.mounted) {
      _showingGuestDetection = false;
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SceneGuestDetectedDialog(
        detected: detected,
        hostName: chat.activeCharacter?.name ?? 'your character',
      ),
    );
    _showingGuestDetection = false;
    if (accepted == true) {
      await chat.acceptDetectedGuest();
    } else {
      chat.dismissDetectedGuest();
    }
  }

  /// Show the `/join` character picker, then bring the chosen library character
  /// into the scene as a Scene Guest. The pending flag is always cleared so the
  /// picker never re-opens for the same request.
  Future<void> _showGuestPickerDialog(
    BuildContext context,
    ChatService chat,
  ) async {
    final initial = chat.pendingGuestPickerFilter;
    if (initial == null || !context.mounted) {
      _showingGuestPicker = false;
      chat.dismissGuestPicker();
      return;
    }
    final full = chat.pendingGuestPickerFull;
    // Full picker: in a group it adds a member; in a 1:1 it converts to a group.
    // Lite picker: Scene Guest in 1:1, or a soft member from the same library
    // pool in a group (`joinableGuestCharacters` forwards there).
    final characters = chat.activeGroup != null
        ? chat.joinableGroupCharacters
        : chat.joinableGuestCharacters;
    final selected = await showDialog<CharacterCard>(
      context: context,
      builder: (_) => SceneGuestPickerDialog(
        characters: characters,
        initialFilter: initial,
        resolveImage: (card) => coverFor(chat, card),
      ),
    );
    _showingGuestPicker = false;
    chat.dismissGuestPicker();
    if (selected != null) {
      if (full) {
        await chat.joinFull(selected);
      } else {
        await chat.joinSceneGuest(selected);
      }
    }
  }
}

/// Replacement for the removed Fork-to-Group wizard: pick a library character
/// and bring them in as a FULL participant via the unified `joinFull` path,
/// converting the current 1:1 into a group in place (with an organic entrance).
/// Same picker as `/join`; only the join tier differs.
Future<void> showConvertToGroupPicker(
  BuildContext context,
  ChatService chat, {
  required File? Function(ChatService chat, CharacterCard card) coverFor,
}) async {
  final selected = await showDialog<CharacterCard>(
    context: context,
    builder: (_) => SceneGuestPickerDialog(
      characters: chat.joinableGuestCharacters,
      initialFilter: '',
      resolveImage: (card) => coverFor(chat, card),
    ),
  );
  if (selected != null) {
    await chat.joinFull(selected);
  }
}

Future<void> showChatImageStudio(
  BuildContext context,
  ChatService chatService, {
  required VoidCallback onAvatarsRefreshed,
}) async {
  // Launch neutral (Freeform / customPrompt); the user picks a Subject inside
  // the studio. Portrait/persona "Set as avatar" side effects happen inside
  // the studio via providers; onAccept remains for any direct launcher.

  final personaService = Provider.of<UserPersonaService>(
    context,
    listen: false,
  );
  final llmProvider = Provider.of<LLMProvider>(context, listen: false);
  final character = chatService.activeCharacter;

  // Get the active LLM service for smart prompt generation
  final llmService = llmProvider.activeService.isReady
      ? llmProvider.activeService
      : null;

  // Get world info if available
  String? worldInfo;
  try {
    final worldRepo = Provider.of<WorldRepository>(context, listen: false);
    final worlds = worldRepo.worlds;
    if (worlds.isNotEmpty) {
      worldInfo = worlds.first.description;
    }
  } catch (_) {}

  // Get recent messages for scene visualization
  List<String>? recentMessages;
  String? lastMessage;
  final messages = chatService.messages;

  if (messages.isNotEmpty) {
    // Collect recent turns so the Freeform "Craft the current scene" path (and
    // the /image scene command) has narrative to distill. Each is stripped of
    // <think> here; the builder caps how many it actually uses.
    recentMessages = messages.reversed
        .take(12)
        .map((m) => m.displayText)
        .where((m) => m.isNotEmpty)
        .map(cleanVisualSourceText)
        .where((m) => m.isNotEmpty)
        .toList()
        .reversed
        .toList();

    // Prefer the most recent *AI/non-user* turn as the narrative anchor so the
    // scene reflects the character's described action rather than the user's
    // just-typed input. Safe fallback to the absolute last message.
    final userName = personaService.persona.name;
    for (final m in messages.reversed) {
      final txt = cleanVisualSourceText(m.displayText);
      if (txt.isNotEmpty && m.sender != userName) {
        lastMessage = txt;
        break;
      }
    }
    lastMessage ??= cleanVisualSourceText(messages.last.displayText);
  }

  // Collect richer context for the Image Studio (expression, time of day, and
  // the group speaker so scene distillation focuses the right character).
  // currentSpeakerId prefers the most recent AI (non-user) sender in a group,
  // so "Focus on X" targets the character whose narrative is illustrated.
  final currentExpression = chatService.currentExpressionLabel;
  final timeOfDay = chatService.timeService.timeOfDay;
  final bool isGroupNonObserver =
      chatService.isGroupMode && !chatService.observerMode;
  String? currentSpeakerId;
  if (isGroupNonObserver && messages.isNotEmpty) {
    final userName = personaService.persona.name; // already obtained above
    for (final m in messages.reversed) {
      final s = m.sender;
      if (s.isNotEmpty && s != userName) {
        currentSpeakerId = s;
        break;
      }
    }
  }
  // lightingHint intentionally omitted at launch (timeOfDay primary from chatService.timeService; richer lightingHint
  // support available via ctx for future callers). Stage 4 wiring complete for all declared fields
  // (currentExpression/timeOfDay/isGroupNonObserver/currentSpeakerId + optional lightingHint); see showChatImageStudio
  // + ImageGenContext + service thins + builder.

  if (!context.mounted) return;

  // onAccept: for legacy direct launchers. For the new button-inside flow the studio _accept decides
  // crop/saveAvatar vs bg set vs user avatar update based on the *chosen* _activeMode at accept time
  // (using providers for storage/persona; portrait char set requires full object so limited here).
  // Pass null for the neutral launch (custom starter); sides for special types work via internal studio logic or save.
  void Function(String path)? onAccept;

  // Stage 3: launch the new from-scratch Image Studio (pre-gen editable workspace first-class).
  // User spec: neutral open (custom as starter), types via internal buttons (popup removed), no pregen boilerplate,
  // visualize uses slider N + think strip on craft, user box text + persona + char visual (no pers) + style to LLM.
  // Re-uses collected raw context. No new private methods added to this surface (thin).
  // "Send to chat": save the studio result to disk and attach it to the
  // conversation as an inline image message (same path the /image slash
  // command uses — ChatServiceImages.addGeneratedImageMessage).
  final imageGenService = Provider.of<ImageGenService>(context, listen: false);
  // Captured pre-dialog for the Expression-pack import refresh below.
  final charRepo = Provider.of<CharacterRepository>(context, listen: false);
  Future<void> onSendToChat(Uint8List bytes, String prompt) async {
    final path = await imageGenService.saveImageToDisk(bytes);
    if (path != null) {
      await chatService.addGeneratedImageMessage(path, prompt);
    }
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ImageStudio(
      mode: ImageGenMode.customPrompt,
      customPrompt: null,
      lastMessage: lastMessage,
      characterName: character?.name,
      characterDescription: character?.description,
      characterPersonality: character?.personality,
      characterDbId: character?.dbId,
      characterImagePath: character?.imagePath,
      // Group cast for the Subject picker: per-member portrait + a caveated
      // whole-cast "group shot". Empty for 1:1 chats. dbId resolves to the
      // member's LIBRARY origin (same routing as the Expression Images menu)
      // so Expression packs land on the shared home, not a throwaway copy.
      groupCharacters: chatService.isGroupMode
          ? [
              for (final c in chatService.groupCharacters)
                (
                  name: c.name,
                  description: c.description,
                  dbId: (chatService.originLibraryCardFor(c) ?? c).dbId,
                ),
            ]
          : const [],
      scenario: cleanVisualSourceText(character?.scenario ?? ''),
      worldInfo: cleanVisualSourceText(worldInfo ?? ''),
      personaName: personaService.persona.name,
      personaText: personaService.persona.persona,
      recentMessages: recentMessages,
      llmService: llmService,
      onAccept: onAccept,
      onSendToChat: onSendToChat,
      // Richer context for better prompts (keep in sync with ImageStudio
      // ctor + service thins + builder).
      currentExpression: currentExpression,
      timeOfDay: timeOfDay,
      lightingHint: null,
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: currentSpeakerId,
      // After an Expression-pack import, reload the library card's avatars
      // and push them onto the live chat card(s) — the same refresh dance
      // the Expression Images menu case does — so the new expressions show
      // without reopening the chat.
      onExpressionsImported: (dbId) async {
        final fresh = await charRepo.getAvatarImages(dbId);
        final targets = [
          ...charRepo.characters,
          ?character,
          ...chatService.groupCharacters,
        ];
        for (final c in targets) {
          if (c.dbId == dbId ||
              chatService.originLibraryCardFor(c)?.dbId == dbId) {
            c.avatarImages = List<AvatarImage>.from(fresh);
          }
        }
        onAvatarsRefreshed();
      },
    ),
  );
}
