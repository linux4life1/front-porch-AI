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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Derive the embedding ID for a character card (must match
/// ChatService._getCharacterIdFromCard). Shared by [MemorySourcesList] and
/// MemoryPanel (Data Bank + active-character exclusion).
String characterEmbeddingId(CharacterCard card) {
  if (card.imagePath != null) {
    return p.basenameWithoutExtension(card.imagePath!);
  }
  return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
}

/// Cross-character memory sources checkbox list (avatars + names) — the
/// "Include memories from other characters" picker inside the Memory (RAG)
/// panel. Selection state lives in MemoryPanel; this list only renders and
/// reports toggles.
class MemorySourcesList extends StatelessWidget {
  final ChatService chatService;
  final Set<String> selectedSources;
  final ValueChanged<String> onToggleSource;

  const MemorySourcesList({
    super.key,
    required this.chatService,
    required this.selectedSources,
    required this.onToggleSource,
  });

  @override
  Widget build(BuildContext context) {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final activeChar = chatService.activeCharacter;
    final activeEmbedId = activeChar != null
        ? characterEmbeddingId(activeChar)
        : '';

    // Get all characters except the current one
    final otherChars = charRepo.characters
        .where((c) => characterEmbeddingId(c) != activeEmbedId)
        .toList();

    if (otherChars.isEmpty) {
      return Text(
        'No other characters available.',
        style: TextStyle(
          fontSize: 10,
          color: AppColors.textTertiary(context),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      children: otherChars.map((char) {
        final embedId = characterEmbeddingId(char);
        final isSelected = selectedSources.contains(embedId);
        return InkWell(
          onTap: () => onToggleSource(embedId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: isSelected
                      ? AppColors.journalAccentOf(context)
                      : AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 8),
                if (char.imagePath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).resolveCharacterImage(char.imagePath!),
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.person,
                        size: 16,
                        color: AppColors.iconSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    char.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? AppColors.textSecondary(context)
                          : AppColors.textTertiary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
