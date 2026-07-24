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

part of '../chat_service.dart';

/// `/image` slash-command wiring + in-chat image message attachment.
///
/// The flow itself (parse → craft → generate → attach) lives in the
/// [ImageCommandService] leaf; this extension only supplies the callbacks
/// that read live ChatService state, mirroring how `_ensureCommandHandler`
/// wires `ChatCommandHandler`. Context assembly here intentionally mirrors
/// the Image Studio launch site (`chat_page._showImageGenDialog`) so a
/// slash-command generation and a studio generation see the same scene —
/// keep the two collection blocks in sync. Raw message text is passed as-is;
/// `ImagePromptBuilder` owns think-block stripping and narrative cleaning.
///
/// Parity: 1:1 and group chats share this one path. The only branch is
/// speaker resolution (active character vs. most recent non-user sender /
/// named member), exactly like the studio launch site. ZERO Realism/Needs
/// work happens here.
extension ChatServiceImages on ChatService {
  /// The crafted /image prompt awaiting user review (null when none). The
  /// desktop dialog and the web modal both key off this.
  String? get pendingImagePromptReview => _pendingImagePromptReview;

  /// Whether an /image run is live (crafting, awaiting review, or
  /// generating) — drives the in-chat "image coming to life" bubble.
  bool get isGeneratingChatImage => _imageCommand?.generating ?? false;

  /// Resolve a pending prompt review: the (possibly edited) prompt to
  /// generate with, or null to cancel. Safe to call when nothing is pending.
  void resolveImagePromptReview(String? prompt) {
    final completer = _imageReviewCompleter;
    if (completer == null) return;
    _pendingImagePromptReview = null;
    _imageReviewCompleter = null;
    completer.complete(prompt);
    notifyListeners();
  }

  ImageCommandService _ensureImageCommand() {
    return _imageCommand ??= ImageCommandService(
      isConfigured: () => _imageGenService?.isConfigured ?? false,
      isBusy: () => _isGenerating || _guestBusy,
      onStatus: (message, {bool sticky = false}) => _setGuestStatus(
        message,
        isError: message.startsWith('⚠'),
        sticky: sticky,
      ),
      craftPrompt: (request) async {
        final crafted = await _craftImageCommandPrompt(request);
        // '' = craft failure (the leaf surfaces the ⚠); null = stop silently.
        if (crafted == null || crafted.trim().isEmpty) return '';
        if (!_storageService.imageGenPromptReview) return crafted;
        // Review-first: park the crafted prompt for the UI (desktop dialog /
        // web modal) and wait for the user's edit or cancel.
        _pendingImagePromptReview = crafted;
        _imageReviewCompleter = Completer<String?>();
        notifyListeners();
        final reviewed = await _imageReviewCompleter!.future;
        if (reviewed == null || reviewed.trim().isEmpty) {
          _setGuestStatus('Image generation cancelled.');
          return null;
        }
        return reviewed.trim();
      },
      generate: (prompt, request) => _imageGenService!.generateImage(
        prompt: prompt,
        negativePrompt: _imageCommandNegative(request),
        isPortrait:
            request.kind == ImageCommandKind.me ||
            request.kind == ImageCommandKind.character,
      ),
      saveImage: (bytes) => _imageGenService!.saveImageToDisk(bytes),
      snapshotSession: () => _currentSessionId,
      attachToChat: (path, prompt, request, launchToken) async {
        // The gen is slow (1-10 min locally); if the user switched chats
        // meanwhile, DON'T append this image to the now-active chat — it was
        // crafted from the ORIGINAL chat's scene and would land on the wrong
        // character. Surface a status and report "not attached".
        if (_sceneChanged(launchToken as String?)) {
          _setGuestStatus(
            '🎨 Image is ready, but you left the chat it was made for — '
            'open that chat and use /image again to add it.',
            isError: true,
          );
          return false;
        }
        final speaker = _resolveImageCommandCharacter(request);
        await addGeneratedImageMessage(
          path,
          prompt,
          senderName: speaker?.name,
          characterId: _activeGroup != null && speaker != null
              ? _getCharacterIdFromCard(speaker)
              : null,
        );
        return true;
      },
      notifyRunStateChanged: notifyListeners,
    );
  }

  /// The character a `/image` request is about: an explicitly named group
  /// member/guest wins, then the most recent non-user speaker (group), then
  /// the active 1:1 character.
  CharacterCard? _resolveImageCommandCharacter(ImageCommandRequest request) {
    final candidates = <CharacterCard>[
      ?_activeCharacter,
      ..._groupCharacters,
      ..._sceneGuestCards,
    ];
    final wanted = request.kind == ImageCommandKind.character
        ? request.text.trim().toLowerCase()
        : '';
    if (wanted.isNotEmpty) {
      for (final c in candidates) {
        if (c.name.toLowerCase() == wanted) return c;
      }
      final partial = candidates
          .where((c) => c.name.toLowerCase().contains(wanted))
          .toList();
      if (partial.length == 1) return partial.first;
    }
    // Most recent AI speaker (matters in groups; in a 1:1 this resolves to
    // the active character anyway).
    final userName = _userPersonaService.persona.name;
    for (final m in _messages.reversed) {
      if (m.isUser || m.sender == 'System' || m.sender == userName) continue;
      for (final c in candidates) {
        if (c.name == m.sender) return c;
      }
    }
    return _activeCharacter ??
        (_groupCharacters.isNotEmpty ? _groupCharacters.first : null);
  }

  /// Negative prompt for a `/image` generation: the user's configured default.
  String _imageCommandNegative(ImageCommandRequest request) =>
      _storageService.imageGenNegativePrompt.trim();

  /// Assemble the live chat context and craft the image prompt through
  /// `ImageGenService.generateSmartPrompt` (LLM when ready, static fallback
  /// otherwise). Mirrors chat_page._showImageGenDialog's collection block.
  Future<String?> _craftImageCommandPrompt(ImageCommandRequest request) async {
    final igs = _imageGenService;
    if (igs == null) return null;

    // scene → customPrompt with no typed text: the builder distills the current
    // scene from the recent narrative (the former "Visualize Scene" mode). custom
    // → customPrompt with the user's free description. raw never reaches craft.
    final mode = switch (request.kind) {
      ImageCommandKind.me => ImageGenMode.userAvatar,
      ImageCommandKind.character => ImageGenMode.characterPortrait,
      _ => ImageGenMode.customPrompt,
    };
    final character = _resolveImageCommandCharacter(request);
    final userName = _userPersonaService.persona.name;

    String? lastMessage;
    final recentMessages = <String>[];
    for (final m in _messages.reversed) {
      if (recentMessages.length >= 12) break;
      final txt = m.displayText;
      if (txt.isEmpty) continue;
      recentMessages.insert(0, txt);
      if (lastMessage == null && !m.isUser && m.sender != 'System') {
        lastMessage = txt;
      }
    }
    lastMessage ??= recentMessages.isNotEmpty ? recentMessages.last : null;

    String? worldInfo;
    final worlds = _worldRepository.worlds;
    if (worlds.isNotEmpty) worldInfo = worlds.first.description;

    final llm = testLlmServiceOverride ?? _llmProvider?.activeService;
    final isGroupNonObserver = isGroupMode && !observerMode;

    // `/image last` distills just the single most recent turn; `/image [scene]`
    // distills the recent run (the builder caps how many it actually uses).
    final effectiveRecent =
        (request.kind == ImageCommandKind.scene && request.text == 'last')
        ? (lastMessage != null ? <String>[lastMessage] : const <String>[])
        : recentMessages;

    return igs.generateSmartPrompt(
      mode: mode,
      style: _storageService.imageGenSettings.imageGenStyle,
      llmService: (llm != null && llm.isReady) ? llm : null,
      customPrompt: request.kind == ImageCommandKind.custom
          ? request.text
          : null,
      lastMessage: lastMessage,
      characterName: character?.name,
      characterDescription: character?.description,
      scenario: character?.scenario,
      worldInfo: worldInfo,
      personaName: userName,
      personaText: _userPersonaService.persona.persona,
      recentMessages: effectiveRecent,
      currentExpression: currentExpressionLabel,
      timeOfDay: _timeService.timeOfDay,
      isGroupNonObserver: isGroupNonObserver,
      currentSpeakerId: isGroupNonObserver ? character?.name : null,
    );
  }
}
