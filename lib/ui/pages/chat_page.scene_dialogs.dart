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
// Scene Guest detection/picker flow, convert-to-group, and the Image Studio
// launcher. Extracted verbatim from chat_page.dart (god-file campaign,
// Tranche A); same library, all privates in scope.

part of 'chat_page.dart';

extension _ChatPageSceneDialogs on _ChatPageState {
  void _showChanceTimeOverlay(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChanceTimeOverlay(),
    );
  }

  /// Show the /image prompt-review dialog and resolve the pending review with
  /// the edited prompt (or null on cancel). Mirrors the guest-picker flow.
  Future<void> _showImagePromptReviewDialog(ChatService chat) async {
    final prompt = chat.pendingImagePromptReview;
    if (prompt == null || !mounted) {
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

  Future<void> _showGuestDetectionDialog(ChatService chat) async {
    final detected = chat.pendingGuestDetection;
    if (detected == null || !mounted) {
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
  Future<void> _showGuestPickerDialog(ChatService chat) async {
    final initial = chat.pendingGuestPickerFilter;
    if (initial == null || !mounted) {
      _showingGuestPicker = false;
      chat.dismissGuestPicker();
      return;
    }
    final full = chat.pendingGuestPickerFull;
    // Full picker: in a group it adds a member; in a 1:1 it converts to a group.
    // Lite picker: a Scene Guest inside a 1:1.
    final characters = full
        ? (chat.activeGroup != null
              ? chat.joinableGroupCharacters
              : chat.joinableGuestCharacters)
        : chat.joinableGuestCharacters;
    final selected = await showDialog<CharacterCard>(
      context: context,
      builder: (_) => SceneGuestPickerDialog(
        characters: characters,
        initialFilter: initial,
        resolveImage: (card) => _coverFor(chat, card),
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

  /// Replacement for the removed Fork-to-Group wizard: pick a library character
  /// and bring them in as a FULL participant via the unified `joinFull` path,
  /// converting the current 1:1 into a group in place (with an organic entrance).
  /// Same picker as `/join`; only the join tier differs.
  Future<void> _showConvertToGroupPicker(ChatService chat) async {
    final selected = await showDialog<CharacterCard>(
      context: context,
      builder: (_) => SceneGuestPickerDialog(
        characters: chat.joinableGuestCharacters,
        initialFilter: '',
        resolveImage: (card) => _coverFor(chat, card),
      ),
    );
    if (selected != null) {
      await chat.joinFull(selected);
    }
  }

  void _showImageGenDialog(
    BuildContext context,
    ChatService chatService,
  ) async {
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
    // (currentExpression/timeOfDay/isGroupNonObserver/currentSpeakerId + optional lightingHint); see _showImageGenDialog
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
    final imageGenService = Provider.of<ImageGenService>(
      context,
      listen: false,
    );
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
          if (mounted) rebuildState(() {});
        },
      ),
    );
  }
}
