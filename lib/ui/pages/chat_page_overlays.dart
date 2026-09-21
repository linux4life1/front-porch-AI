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

part of 'chat_page.dart';

/// Chat surface (background + bubbles) and page-level overlays.
extension _ChatPageOverlays on _ChatPageState {
  Widget _buildChatSurface({
    required BuildContext context,
    required ChatService chatService,
    required CharacterCard? character,
    required List<ChatMessage> messages,
    required bool isGroup,
  }) {
    return Builder(
      builder: (context) {
        final storageService = Provider.of<StorageService>(context);
        final chatService = Provider.of<ChatService>(context, listen: false);
        final themeOverrides = chatService.sessionThemeOverrides;
        final themePreset = ChatThemePreset.byId(themeOverrides.themeId);
        final bgKey = themePreset != null
            ? themeOverrides.resolvedBackgroundKey(themePreset)
            : storageService.uiSettings.chatBackground;
        const bgAssets = {
          'noir': 'assets/backgrounds/noir.png',
          'fantasy': 'assets/backgrounds/fantasy.png',
          'grid': 'assets/backgrounds/grid.png',
          'roman_market': 'assets/backgrounds/roman_market.png',
          'enchanted_wood': 'assets/backgrounds/enchanted_wood.png',
          'ocean_depth': 'assets/backgrounds/ocean_depth.png',
          'steampunk_bg': 'assets/backgrounds/steampunk_bg.png',
          'cyberpunk_bedroom': 'assets/backgrounds/cyberpunk_bedroom.png',
          'coffee_shop': 'assets/backgrounds/coffee_shop.png',
          'beach': 'assets/backgrounds/beach.png',
          'futuristic_city': 'assets/backgrounds/futuristic_city.png',
          'edm_rave': 'assets/backgrounds/edm_rave.png',
          'cozy_library': 'assets/backgrounds/cozy_library.png',
          'rainy_japan': 'assets/backgrounds/rainy_japan.png',
          'space_station': 'assets/backgrounds/space_station.png',
          'enchanted_forest': 'assets/backgrounds/enchanted_forest.png',
          'anime_cherry_blossom': 'assets/backgrounds/anime_cherry_blossom.png',
          'anime_rooftop': 'assets/backgrounds/anime_rooftop.png',
          'anime_rooftop_sunset': 'assets/backgrounds/anime_rooftop_sunset.png',
          'cherry_blossom': 'assets/backgrounds/cherry_blossom.png',
          'beach_waves': 'assets/backgrounds/beach_waves.png',
          'waifu_gaming_room': 'assets/backgrounds/waifu_gaming_room.png',
          'waifu_beach_bar': 'assets/backgrounds/waifu_beach_bar.png',
          'waifu_garden': 'assets/backgrounds/waifu_garden.png',
          'waifu_neon': 'assets/backgrounds/waifu_neon.png',
          'waifu_beach': 'assets/backgrounds/waifu_beach.png',
        };
        final bgPath = bgAssets[bgKey];
        final bgPathExists = bgPath != null;

        // Check for matching custom background
        Map<String, String>? customEntry;
        if (!bgPathExists) {
          try {
            customEntry = storageService.uiSettings.customBackgrounds
                .firstWhere((e) => e['id'] == bgKey);
          } catch (_) {}
        }
        // Memoized: this builder reruns on every
        // streaming token batch; a per-rebuild
        // existsSync is the io-lint bug class.
        final hasCustomBg =
            customEntry != null &&
            _bgExistsCache.putIfAbsent(
              customEntry['filePath']!,
              () => File(
                customEntry!['filePath']!,
              ).existsSync(), // io-ok: memoized, once per path
            );

        return Stack(
          children: [
            if (bgPath != null) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(bgPath, fit: BoxFit.cover),
                ),
              ),
            ],
            // Expression background sprite
            Consumer<ChatService>(
              builder: (context, chat, _) {
                final storage = Provider.of<StorageService>(
                  context,
                  listen: false,
                );
                final displayMode =
                    storage.expressionSettings.expressionDisplayMode;
                final isEnabled = storage.expressionSettings.expressionEnabled;
                if (!isEnabled ||
                    displayMode == 'sidebar' ||
                    chat.isEvaluatingRealism) {
                  return const SizedBox.shrink();
                }
                final char = character;
                if (char == null ||
                    expressionsFrom(char.avatarImages).isEmpty) {
                  return const SizedBox.shrink();
                }
                final avatar = chat.resolveExpressionAvatar(
                  char,
                  rerollIfSame: storage.expressionSettings.expressionRerollSame,
                );
                if (avatar == null) {
                  return const SizedBox.shrink();
                }
                final avatarDir = storage.characterAvatarDir(char.name);
                final avatarFile = File('${avatarDir.path}/${avatar.filename}');
                return Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      child: Stack(
                        key: ValueKey('expr_bg_${avatar.id}'),
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            avatarFile,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (bgPath != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                ),
              ),
            if (!bgPathExists && hasCustomBg) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: FileImage(File(customEntry['filePath']!)),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: Colors.black.withValues(alpha: 0.45)),
                ),
              ),
            ],
            ChatMessageList(
              messages: messages,
              controller: _scrollController,
              resolveSpeaker: (msg) => _resolveSpeaker(chatService, msg),
              characterFor: (msg) => isGroup && !msg.isUser
                  ? resolveGroupSpeakerForMessage(
                      chatService.groupCharacters,
                      msg,
                    )
                  : character,
              chatService: chatService,
              bubbleKeyOf: _bubbleKeyFor,
              jumpFlash: _jumpFlashMessage,
              generatingImage: chatService.isGeneratingChatImage,
              externalImagesAllowed: _externalImagesAllowed,
              onRequestImagePermission: _requestExternalImagePermission,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildPageOverlays({
    required BuildContext context,
    required ChatService chatService,
    required CharacterCard? character,
    required bool isGroup,
  }) {
    return [
      if (chatService.isLoadingSession)
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.backgroundOf(context),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ),
      // Voice call overlay
      if (_isCallActive && character != null && !isGroup)
        Positioned.fill(
          child: CallOverlay(
            character: character,
            onEndCall: () {
              rebuildState(() => _isCallActive = false);
            },
          ),
        ),
      // Realism Engine processing overlays
      if (chatService.isEvaluatingRealism ||
          chatService.isProcessingGreeting ||
          chatService.isVerifyingRealism)
        RealismProcessingOverlay(
          chatService: chatService,
          isGreeting: chatService.isProcessingGreeting,
        ),
      // Objective completion check overlay (only when realism isn't already showing)
      if (chatService.isCheckingCompletion &&
          !chatService.isEvaluatingRealism &&
          !chatService.isProcessingGreeting)
        ObjectiveCheckOverlay(chatService: chatService),
      // ONNX model download progress overlay
      Positioned.fill(
        child: Consumer<ExpressionClassifierService>(
          builder: (context, classifier, _) {
            if (!classifier.isDownloading) return const SizedBox.shrink();
            return OnnxDownloadOverlay(classifierService: classifier);
          },
        ),
      ),
    ];
  }
}
