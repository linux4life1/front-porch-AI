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

part of 'character_grid_card.dart';

/// The card's face: the tiny overlay layout and the full portrait + name +
/// tags layout, picked by width in [CharacterGridCard].
extension _CharacterGridCardBody on CharacterGridCard {
  Widget _tinyBody(BuildContext context, CharacterCard character) {
    return Stack(
      fit: StackFit.expand,
      children: [
        character.imagePath != null
            ? _coverImage(context, onResolveCharImage(character), size: 32)
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

  Widget _fullBody(
    BuildContext context,
    CharacterCard character,
    int msgCount,
    bool isCompact,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: isCompact ? 4 : 3,
          child: character.imagePath != null
              ? _coverImage(
                  context,
                  onResolveCharImage(character),
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
