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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/home/cards/home_card_menu.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_ghost.dart';
import 'package:front_porch_ai/ui/pages/home/cards/library_drag_payload.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/character_card_grid.dart'
    show kFolderDragHoldDelay;
import 'package:front_porch_ai/utils/utils.dart';

part 'character_grid_card.body.dart';

/// A single character card in the home grid: draggable (for folder organizing),
/// selectable, with the avatar/name/message-count body and a right-click
/// context menu. Scene Guests (Lite NPCs) get a "Guest" badge. Extracted
/// verbatim from CharacterCardGrid — behavior-preserving.
class CharacterGridCard extends StatelessWidget {
  const CharacterGridCard({
    super.key,
    required this.character,
    required this.activeFolderId,
    required this.messageCountCache,
    required this.isSelecting,
    required this.isOrganizing,
    required this.selectedCharacterIds,
    required this.onTapCharacter,
    required this.onToggleSelect,
    required this.onContextMenuAction,
    required this.onResolveCharImage,
    this.imageCacheEpoch = 0,
    this.dragSelection,
    this.dimmed = false,
    this.onDragStarted,
    this.onDragEnded,
  });

  final CharacterCard character;
  final String? activeFolderId;
  final Map<String, int> messageCountCache;
  final bool isSelecting;
  final bool isOrganizing;
  final Set<String> selectedCharacterIds;
  final Future<void> Function(CharacterCard character) onTapCharacter;
  final void Function(CharacterCard character) onToggleSelect;
  final void Function(String action, CharacterCard character)
  onContextMenuAction;
  final File Function(CharacterCard card) onResolveCharImage;

  /// From [CharacterRepository.coverEpoch] — forces [Image.file] to drop a
  /// stale frame when the portrait is rewritten in place (same path).
  final int imageCacheEpoch;

  /// Set while this card is picked: holding it then drags every pick, with
  /// the stacked ghost. Null keeps the one-card drag.
  final LibraryDragPayload? dragSelection;

  /// Drawn at 40% while the picks it belongs to are being dragged.
  final bool dimmed;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  /// Delegates to the canonical stable group ID.
  String _getCharacterIdFromCard(CharacterCard card) => card.stableGroupId;

  /// The person icon a card shows when it has no portrait of its own.
  Widget _noPortrait(BuildContext context, double size) => Container(
    color: AppColors.surfaceContainerOf(context),
    child: Icon(
      Icons.person,
      size: size,
      color: AppColors.iconSecondary(context),
    ),
  );

  /// A card made without a portrait still carries a flat coloured picture
  /// (the card file needs one); it gets the person icon like a card with no
  /// picture at all. Until the probe has answered, the icon stands in too, so
  /// the flat colour never flashes up first; the picture is drawn only once
  /// the probe says it is real. Answers are cached, so a known card paints
  /// its final face on the first frame.
  Widget _coverImage(BuildContext context, File file, {required double size}) {
    return FutureBuilder<bool>(
      future: PlaceholderPortraitProbe.check(file, version: imageCacheEpoch),
      initialData: PlaceholderPortraitProbe.known(
        file,
        version: imageCacheEpoch,
      ),
      builder: (context, placeholder) => placeholder.data == false
          ? _portraitImage(context, file, size: size)
          : _noPortrait(context, size),
    );
  }

  Widget _portraitImage(
    BuildContext context,
    File file, {
    required double size,
  }) {
    return Image.file(
      file,
      key: ValueKey(
        '${character.dbId ?? character.name}|${file.path}|$imageCacheEpoch',
      ),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      gaplessPlayback: false,
      // Decode at grid-tile size, not source size: ~1024² portraits are
      // ~4 MB decoded EACH, which thrashed the 100 MB image cache on any
      // decent-sized library and forced re-decodes on every scroll. 512px
      // covers the largest tile at 2x DPR at a quarter of the memory.
      cacheWidth: 512,
      errorBuilder: (_, _, _) => _noPortrait(context, size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final picks = dragSelection;
    // Scene Guests (Lite NPCs) are real library cards (so they persist and
    // can be deleted here), but badge them so they're distinguishable from
    // regular characters in the grid.
    final face = character.isLite
        ? Stack(
            children: [
              _buildCharacterCardInner(context, character),
              Positioned(top: 6, left: 6, child: _guestBadge(context)),
            ],
          )
        : _buildCharacterCardInner(context, character);
    // Always an Opacity, so dimming mid-drag never rebuilds the draggable.
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: LongPressDraggable<Object>(
        data: picks ?? character,
        delay: kFolderDragHoldDelay,
        dragAnchorStrategy: picks == null
            ? childDragAnchorStrategy
            : LibraryDragGhost.anchor,
        feedback: picks == null
            ? _singleFeedback(context)
            : LibraryDragGhost(
                count: picks.count,
                name: character.name,
                cover: _ghostCover(context),
              ),
        childWhenDragging: picks == null
            ? Opacity(
                opacity: 0.3,
                child: _buildCharacterCardInner(context, character),
              )
            : face,
        onDragStarted: onDragStarted,
        onDragEnd: (_) => onDragEnded?.call(),
        child: face,
      ),
    );
  }

  Widget _ghostCover(BuildContext context) => character.imagePath != null
      ? _coverImage(context, onResolveCharImage(character), size: 32)
      : ColoredBox(
          color: AppColors.surfaceContainerOf(context),
          child: Icon(
            Icons.person,
            size: 40,
            color: AppColors.iconSecondary(context),
          ),
        );

  Widget _singleFeedback(BuildContext context) => Material(
    color: Colors.transparent,
    child: SizedBox(
      width: 150,
      height: 200,
      child: Card(
        color: AppColors.cardOf(context),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: character.imagePath != null
            ? _coverImage(context, onResolveCharImage(character), size: 48)
            : Icon(
                Icons.person,
                size: 64,
                color: AppColors.iconSecondary(context),
              ),
      ),
    ),
  );

  /// Small "Guest" chip overlaid on Scene Guest (Lite NPC) cards in the grid.
  Widget _guestBadge(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.relationshipAccent.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'Guest',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
  );

  Widget _buildCharacterCardInner(
    BuildContext context,
    CharacterCard character,
  ) {
    final charId = _getCharacterIdFromCard(character);
    final msgCount = messageCountCache[charId] ?? 0;

    final stringId = _getCharacterIdFromCard(character);
    final isSelectedCard = selectedCharacterIds.contains(stringId);

    return Card(
      color: AppColors.cardOf(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelectedCard
              ? AppColors.porchTerracottaOf(context)
              : AppColors.borderOf(context).withValues(alpha: 0.3),
          width: isSelectedCard ? 2.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          // Positioned.fill for the same reason folder_grid_card needs it: a
          // bare Stack child gets LOOSE constraints and top-left alignment, so
          // the InkWell shrink-wraps its content instead of covering the card.
          // This one hides the bug today because its content is an image that
          // fills anyway — but it leaves LayoutBuilder measuring the wrong
          // width, and the tap target would collapse the moment this card ever
          // renders text-sized content. Same defect, caught before it shipped.
          Positioned.fill(
            child: InkWell(
              onTap: () async {
                if (isSelecting || isOrganizing) {
                  onToggleSelect(character);
                  return;
                }
                await onTapCharacter(character);
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 200;
                  final isTiny = constraints.maxWidth < 160;

                  if (isTiny) {
                    return _tinyBody(context, character);
                  }
                  return _fullBody(context, character, msgCount, isCompact);
                },
              ),
            ),
          ),
          if (isSelecting || isOrganizing)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelectedCard
                      ? (isOrganizing
                            ? AppColors.porchHoneyOf(context)
                            : AppColors.porchTerracottaOf(context))
                      : AppColors.resolve(
                          context,
                          Colors.black54,
                          Colors.black12,
                        ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelectedCard
                        ? (isOrganizing
                              ? AppColors.porchHoneyOf(context)
                              : AppColors.porchTerracottaOf(context))
                        : AppColors.resolve(
                            context,
                            Colors.white38,
                            Colors.black38,
                          ),
                    width: 2,
                  ),
                ),
                child: isSelectedCard
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          if (!isSelecting && !isOrganizing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: (details) {
                  final position = details.globalPosition;
                  showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      position.dx,
                      position.dy,
                      position.dx,
                      position.dy,
                    ),
                    color: AppColors.surfaceContainerOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    items: characterCardMenuItems(
                      context,
                      inFolder: activeFolderId != null,
                    ),
                  ).then((value) {
                    if (value == null) return;
                    onContextMenuAction(value, character);
                  });
                },
                child: const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }
}
