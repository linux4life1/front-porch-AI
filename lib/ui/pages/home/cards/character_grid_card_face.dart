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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';

/// The person icon a card shows when it has no portrait of its own.
class CharacterGridCardNoPortrait extends StatelessWidget {
  const CharacterGridCardNoPortrait({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceContainerOf(context),
    child: Icon(
      Icons.person,
      size: size,
      color: AppColors.iconSecondary(context),
    ),
  );
}

/// A character's portrait on a home grid card.
///
/// A card made without a portrait still carries a flat coloured picture
/// (the card file needs one); it gets the person icon like a card with no
/// picture at all. Until the probe has answered, the icon stands in too, so
/// the flat colour never flashes up first; the picture is drawn only once
/// the probe says it is real. Answers are cached, so a known card paints
/// its final face on the first frame.
class CharacterGridCardCover extends StatelessWidget {
  const CharacterGridCardCover({
    super.key,
    required this.character,
    required this.file,
    required this.imageCacheEpoch,
    required this.size,
  });

  final CharacterCard character;
  final File file;

  /// From [CharacterRepository.coverEpoch] — forces [Image.file] to drop a
  /// stale frame when the portrait is rewritten in place (same path).
  final int imageCacheEpoch;
  final double size;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: PlaceholderPortraitProbe.check(file, version: imageCacheEpoch),
      initialData: PlaceholderPortraitProbe.known(
        file,
        version: imageCacheEpoch,
      ),
      builder: (context, placeholder) => placeholder.data == false
          ? _portraitImage()
          : CharacterGridCardNoPortrait(size: size),
    );
  }

  Widget _portraitImage() {
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
      errorBuilder: (_, _, _) => CharacterGridCardNoPortrait(size: size),
    );
  }
}

/// The card face for tiny tiles: portrait with the name over a scrim.
class CharacterGridCardTinyBody extends StatelessWidget {
  const CharacterGridCardTinyBody({
    super.key,
    required this.character,
    required this.onResolveCharImage,
    required this.imageCacheEpoch,
  });

  final CharacterCard character;
  final File Function(CharacterCard card) onResolveCharImage;
  final int imageCacheEpoch;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        character.imagePath != null
            ? CharacterGridCardCover(
                character: character,
                file: onResolveCharImage(character),
                imageCacheEpoch: imageCacheEpoch,
                size: 32,
              )
            : Container(
                color: AppColors.surfaceContainerOf(context),
                child: Icon(
                  Icons.person,
                  size: 32,
                  color: AppColors.iconSecondary(context),
                ),
              ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppColors.resolve(context, Colors.black87, Colors.black54),
                  Colors.transparent,
                ],
              ),
            ),
            child: Text(
              character.name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// The full card face: portrait, name + message count, and tags (or the
/// description when there are none).
class CharacterGridCardFullBody extends StatelessWidget {
  const CharacterGridCardFullBody({
    super.key,
    required this.character,
    required this.onResolveCharImage,
    required this.imageCacheEpoch,
    required this.msgCount,
    required this.isCompact,
  });

  final CharacterCard character;
  final File Function(CharacterCard card) onResolveCharImage;
  final int imageCacheEpoch;
  final int msgCount;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: isCompact ? 4 : 3,
          child: character.imagePath != null
              ? CharacterGridCardCover(
                  character: character,
                  file: onResolveCharImage(character),
                  imageCacheEpoch: imageCacheEpoch,
                  size: isCompact ? 32 : 64,
                )
              : Container(
                  color: AppColors.surfaceContainerOf(context),
                  child: Icon(
                    Icons.person,
                    size: isCompact ? 32 : 64,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
        ),
        Expanded(
          flex: 1,
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 6.0 : 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        character.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isCompact ? 12 : null,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (msgCount > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 11,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$msgCount',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: isCompact ? 10 : 11,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (!isCompact) ...[
                  const SizedBox(height: 4),
                  if (character.tags.isNotEmpty)
                    Flexible(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: character.tags
                            .take(3)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.porchAmberOf(
                                    context,
                                  ).withValues(alpha: 0.18),
                                  border: Border.all(
                                    color: AppColors.porchAmberOf(
                                      context,
                                    ).withValues(alpha: 0.4),
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    color: AppColors.porchAmberOf(context),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  else
                    Flexible(
                      child: Text(
                        character.formattedDescription,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
