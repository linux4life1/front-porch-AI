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

// The "Characters" step of ForkToGroupPage (roster + responsive add-grid).
// Split into its own file to keep each file under the project size cap; shared
// helpers (forkAvatar/forkAccent/forkStepHeader) live in fork_to_group_steps.dart.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/fork_to_group_steps.dart';

class ForkCharactersStep extends StatelessWidget {
  const ForkCharactersStep({
    super.key,
    required this.original,
    required this.added,
    required this.available,
    required this.onAdd,
    required this.onRemove,
    required this.onReorder,
  });

  final CharacterCard? original;
  final List<CharacterCard> added;
  final List<CharacterCard> available;
  final void Function(CharacterCard) onAdd;
  final void Function(CharacterCard) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        forkStepHeader(
          context,
          'Characters',
          subtitle:
              'Choose who joins ${original?.name ?? "the chat"}. Add at least '
              'one. Their order is the order they enter.',
        ),
        Text(
          'Added (${added.length})',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        if (added.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'No one added yet — pick from below.',
              style: TextStyle(color: AppColors.textTertiary(context)),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: added.length,
            onReorder: onReorder,
            itemBuilder: (ctx, i) {
              final c = added[i];
              return Card(
                key: ValueKey(c.name),
                color: AppColors.cardOf(context),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: forkAvatar(context, c),
                  title: Text(
                    c.name,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.iconSecondary(context),
                    onPressed: () => onRemove(c),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 20),
        Text(
          'Add characters',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary(context),
          ),
        ),
        const SizedBox(height: 8),
        if (available.isEmpty)
          Text(
            'No other characters available. Import or create some first.',
            style: TextStyle(color: AppColors.textTertiary(context)),
          )
        else
          // Responsive grid that fills the available width: as many ~260px-wide
          // cards per row as fit, each showing a full name + description snippet.
          LayoutBuilder(
            builder: (context, constraints) {
              // Tiles scale with the window: 1–3 columns depending on width,
              // each filling its share so wide windows get big cards rather
              // than a cluster of small ones.
              const minTileWidth = 360.0;
              final columns = (constraints.maxWidth / minTileWidth)
                  .floor()
                  .clamp(1, 3);
              final tileWidth =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: available.map((c) {
                  return SizedBox(
                    width: tileWidth,
                    child: Material(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onAdd(c),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              forkAvatar(context, c, radius: 30),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                    if (c.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        c.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textTertiary(context),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.add_circle_outline,
                                size: 24,
                                color: forkAccent(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }
}
