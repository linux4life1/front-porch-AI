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
// The two big blocks of the ChatPage right sidebar: the focused character's
// portrait (expressions / gallery face ring / chevrons) and the Main Settings
// popup. Extracted verbatim from _buildRightSidebar's Column (god-file
// campaign, Tranche A); same library, all privates in scope.

part of 'chat_page.dart';

extension _ChatPageSidebarWidgets on _ChatPageState {
  /// Expression image / gallery face / default portrait for the focused
  /// character — verbatim the first child of the old _buildRightSidebar Column.
  Widget _buildSidebarPortrait(CharacterCard character, bool isGroup) {
    return Consumer<ChatService>(
      builder: (context, chat, _) {
        final storage = Provider.of<StorageService>(context, listen: false);
        final isExpressionEnabled = storage.expressionEnabled;
        // Expression-only (looks filtered out) so a looks-only character
        // never trips the expression path, and prime/neutral fallbacks
        // never resolve to a gallery look.
        final expressionAvatars = expressionsFrom(character.avatarImages);
        final hasAvatars = expressionAvatars.isNotEmpty;

        File? expressionFile;
        String? expressionKey;
        String? expressionEmoji;

        if (isExpressionEnabled && hasAvatars && !chat.isEvaluatingRealism) {
          final avatar = chat.resolveExpressionAvatar(
            character,
            rerollIfSame: storage.expressionRerollSame,
          );
          if (avatar != null) {
            final avatarDir = storage.characterAvatarDir(character.name);
            expressionFile = File('${avatarDir.path}/${avatar.filename}');
            expressionKey = avatar.id;
            final label = chat.currentExpressionLabel;
            expressionEmoji = label != null ? EmotionLabels.emoji[label] : null;
          }
        }

        File? displayFile;
        Widget? fallbackWidget;

        // Gallery face ring (plain chat only) — populated in the
        // expressions-OFF branch below, consumed by the chevron overlay.
        // lookKey is the LIBRARY character id (the collection is global per
        // library character): in a group the focused member card has a null
        // dbId, so we resolve the origin library card — same routing the
        // Expression Images editor uses — and never key by an empty string.
        List<String> faceRing = const [];
        int facePosition = 0;
        int faceTotal = 0;
        String? lookKey;
        bool showLookChevrons = false;

        if (expressionFile != null) {
          displayFile = expressionFile;
        } else if (isExpressionEnabled && hasAvatars) {
          // Apply fallback behavior. Only when the character actually
          // HAS expression images: with none, the old fallback ladder
          // ended at the raw portrait — ignoring the gallery ring, so
          // starring a look changed the library card but never this
          // sidebar (field report). Expressionless characters now take
          // the plain-chat ring branch below (star default + chevrons)
          // even while the global expression toggle is on.
          final fallback = storage.expressionFallback;
          if (fallback == 'none') {
            return const SizedBox.shrink();
          } else if (fallback == 'emoji') {
            final label = chat.currentExpressionLabel ?? 'neutral';
            final emoji = EmotionLabels.emoji[label] ?? '🎭';
            fallbackWidget = Center(
              child: Text(
                emoji,
                style: TextStyle(fontSize: _sidebarWidth * 0.5),
              ),
            );
          } else if (fallback == 'prime') {
            // Show prime avatar (expression-only — never a gallery look).
            final primeAvatar =
                expressionAvatars
                    .where(
                      (a) => a.displayOrder + 1 == character.primeAvatarIndex,
                    )
                    .isEmpty
                ? expressionAvatars.first
                : expressionAvatars.firstWhere(
                    (a) => a.displayOrder + 1 == character.primeAvatarIndex,
                  );
            final avatarDir = storage.characterAvatarDir(character.name);
            displayFile = File('${avatarDir.path}/${primeAvatar.filename}');
            expressionKey = primeAvatar.id;
          } else {
            // 'neutral' or default: show neutral avatar if available, else character image
            final neutralAvatar = expressionAvatars
                .where((a) => a.label?.toLowerCase() == 'neutral')
                .toList();
            if (neutralAvatar.isNotEmpty) {
              final avatarDir = storage.characterAvatarDir(character.name);
              displayFile = File(
                '${avatarDir.path}/${neutralAvatar.first.filename}',
              );
              expressionKey = neutralAvatar.first.id;
              expressionEmoji = EmotionLabels.emoji['neutral'];
            }
            if (displayFile == null && character.imagePath != null) {
              displayFile = _resolveCharImage(character.imagePath!);
            }
          }
        } else {
          // Expressions disabled — the plain-chat face. The gallery face
          // ring (portrait + looks + the ★-starred expression, if any)
          // drives what shows here; the chevrons flip through it, and the
          // ★ star is the default. Resolve the library card so group
          // members (null dbId) still key by their origin and pull the
          // global collection.
          final libraryCard = isGroup
              ? (chat.originLibraryCardFor(character) ?? character)
              : character;
          lookKey = libraryCard.dbId;
          if (lookKey != null && lookKey.isNotEmpty) {
            final allImages = libraryCard.avatarImages ?? const <AvatarImage>[];
            final favId = libraryCard.frontPorchExtensions?.favoriteAvatarId;
            AvatarImage? favorite;
            if (favId != null) {
              for (final a in allImages) {
                if (a.id == favId) {
                  favorite = a;
                  break;
                }
              }
            }
            faceRing = buildFaceRing(
              looks: looksFrom(allImages),
              hasImagePath: character.imagePath != null,
              favorite: favorite,
            );
            final faceDisplay = resolveFaceDisplay(
              ring: faceRing,
              allImages: allImages,
              selectedFaceId: chat.selectedLookFor(lookKey),
            );
            showLookChevrons = faceDisplay.showChevrons;
            facePosition = faceDisplay.position;
            faceTotal = faceDisplay.total;
            if (faceDisplay.image != null) {
              displayFile = faceDisplay.image!.resolveFile(
                storage.characterBaseDir(libraryCard.name).path,
              );
              expressionKey = 'face_${faceDisplay.image!.id}';
            } else if (character.imagePath != null) {
              displayFile = _resolveCharImage(character.imagePath!);
            }
          } else if (character.imagePath != null) {
            displayFile = _resolveCharImage(character.imagePath!);
          }
        }

        if (fallbackWidget != null) return fallbackWidget;
        if (displayFile == null) return const SizedBox.shrink();

        final avatarLocked =
            character.frontPorchExtensions?.avatarLocked ?? false;
        final avatarSize = avatarLocked
            ? _sidebarWidth.clamp(0, 300).toDouble()
            : _sidebarWidth;

        Widget avatar = SizedBox(
          height: avatarSize,
          width: avatarSize,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                child: Image.file(
                  displayFile,
                  key: ValueKey(expressionKey ?? 'default'),
                  width: avatarSize,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.resolve(
                      context,
                      Colors.black26,
                      Colors.black.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.person,
                      color: AppColors.iconSecondary(context),
                      size: 64,
                    ),
                  ),
                ),
              ),
              // Emotion label badge
              if (expressionEmoji != null)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: EmojiBurst(
                    emoji: expressionEmoji,
                    enabled: storage.expressionEmojiBurst,
                    generating: chat.isGenerating,
                    size: storage.expressionEmojiBurstSize,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.resolve(
                          context,
                          Colors.black.withValues(alpha: 0.7),
                          Colors.black.withValues(alpha: 0.45),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            expressionEmoji,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Gallery face chevrons + counter (plain chat, >1 face).
              if (showLookChevrons && lookKey != null)
                Positioned.fill(
                  child: LookChevronBar(
                    position: facePosition,
                    total: faceTotal,
                    // Read the current selection LIVE at tap time (not a
                    // captured value) so rapid taps advance step-by-step
                    // instead of all computing from one stale selection.
                    onFlip: (delta) => chat.setLookForCharacter(
                      lookKey!,
                      flipFace(
                        faceRing,
                        chat.selectedLookFor(lookKey) ??
                            (faceRing.isEmpty ? null : faceRing.first),
                        delta,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
        if (avatarLocked && _sidebarWidth > 300) {
          avatar = Align(alignment: Alignment.topRight, child: avatar);
        }
        return avatar;
      },
    );
  }

  /// The ONE character editor (EditCharacterPage) in a dialog shell — full
  /// feature set with honest Save/Cancel; nothing persists until Save.
  /// OPEN_SECTION=edit reuses this path and scrolls the Relationship header
  /// block (20px gap + header) below the Details tab. No Save.
  Future<void> _openEditCharacterDialog(
    CharacterCard character, {
    bool ensureRelationshipVisible = false,
  }) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final opened = showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 780,
          height: MediaQuery.of(dialogCtx).size.height - 96,
          child: EditCharacterPage(
            character: character,
            // Light refresh only — never the full setActiveCharacter dance,
            // which cancels in-flight generation, full-reloads on rename,
            // and leaves group mode.
            onSaved: (saved) async =>
                chatService.refreshActiveCharacterCard(saved),
          ),
        ),
      ),
    );
    if (ensureRelationshipVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          OpenSectionEnv.ensureRelationshipHeaderVisible(context);
        });
      });
    }
    await opened;
    if (!mounted) return;
    rebuildState(() {});
  }

  /// The "Main Settings" popup button — verbatim the second child of the old
  /// _buildRightSidebar Column.
  Widget _buildSidebarMainSettings(
    ChatService chatService,
    CharacterCard character,
    bool isGroup,
  ) {
    return Container(
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
        child: PopupMenuButton<String>(
          color: AppColors.surfaceContainerOf(context),
          elevation: 8,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary(context),
            side: BorderSide(
              color: AppColors.borderOf(context).withValues(alpha: 0.4),
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: AppColors.borderOf(context).withValues(alpha: 0.3),
            ),
          ),
          offset: const Offset(0, 8),
          onSelected: (value) async {
            switch (value) {
              case 'edit_character':
                await _openEditCharacterDialog(character);
                break;
              case 'expressions':
                final storage = Provider.of<StorageService>(
                  context,
                  listen: false,
                );
                final repo = Provider.of<CharacterRepository>(
                  context,
                  listen: false,
                );
                // In a group, members are single-avatar copies — editing
                // one would write to a throwaway id and never inherit. Route
                // the editor at the real LIBRARY character (the shared home)
                // so expression edits persist and flow back to the group.
                // 1:1 already passes the library character itself.
                final exprTarget = isGroup
                    ? (chatService.originLibraryCardFor(character) ?? character)
                    : character;
                await showAvatarGallery(
                  context: context,
                  character: exprTarget,
                  repository: repo,
                  storage: storage,
                  mode: WardrobeMode.inChat,
                  chatService: chatService,
                );
                // Push the freshly edited library images onto the live
                // member card so the group reflects them immediately
                // (inheritance otherwise skips members already populated).
                // The gallery controller keeps exprTarget fresh; copy both
                // the image list AND the prime index so the member's
                // default-emotion resolution can't lag the library edit.
                if (!identical(exprTarget, character)) {
                  character.avatarImages = exprTarget.avatarImages == null
                      ? null
                      : List<AvatarImage>.from(exprTarget.avatarImages!);
                  character.primeAvatarIndex = exprTarget.primeAvatarIndex;
                }
                if (mounted) rebuildState(() {});
                break;
              case 'ui':
                showDialog(
                  context: context,
                  builder: (context) => UiSettingsDialog(character: character),
                );
                break;
              case 'chat':
                showDialog(
                  context: context,
                  builder: (context) => const ChatSettingsDialog(),
                );
                break;
              case 'model':
                showDialog(
                  context: context,
                  builder: (context) => const ModelSettingsDialog(),
                );
                break;
              case 'tts':
                showDialog(
                  context: context,
                  builder: (context) => const TtsSettingsDialog(),
                );
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit_character',
              child: SettingsMenuItem(
                icon: Icons.edit_outlined,
                label: 'Edit Character',
              ),
            ),
            PopupMenuItem(
              value: 'expressions',
              child: SettingsMenuItem(
                icon: Icons.photo_library_outlined,
                label: 'Avatar Gallery',
              ),
            ),
            PopupMenuItem(
              value: 'ui',
              child: SettingsMenuItem(
                icon: Icons.tune_outlined,
                label: 'UI Settings',
              ),
            ),
            PopupMenuDivider(height: 1),
            PopupMenuItem(
              value: 'chat',
              child: SettingsMenuItem(
                icon: Icons.chat_bubble_outline,
                label: 'Chat Settings',
              ),
            ),
            PopupMenuItem(
              value: 'model',
              child: SettingsMenuItem(
                icon: Icons.memory_outlined,
                label: 'Model Settings',
              ),
            ),
            PopupMenuItem(
              value: 'tts',
              child: SettingsMenuItem(
                icon: Icons.volume_up_outlined,
                label: 'TTS Settings',
              ),
            ),
          ],
          // Label inherits OutlinedButton foreground (textSecondary) —
          // hard-coded white70 was washed out on light sidebar paper (P3).
          child: const Text('Main Settings', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
