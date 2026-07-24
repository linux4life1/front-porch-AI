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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// Result of the single-file same-name import dialog.
///
/// - [keepBoth]: insert a new library entry (default bulk behavior).
/// - [replaceTarget]: update that existing card in place (chats kept).
/// - null return from [showImportNameCollisionDialog]: user cancelled.
class ImportNameCollisionResult {
  final bool keepBoth;
  final CharacterCard? replaceTarget;

  const ImportNameCollisionResult.keepBoth()
      : keepBoth = true,
        replaceTarget = null;

  const ImportNameCollisionResult.replace(CharacterCard target)
      : keepBoth = false,
        replaceTarget = target;
}

/// Asks what to do when importing a card whose display name already exists
/// but whose stableId does not match any library character.
///
/// Returns null on cancel / dismiss.
Future<ImportNameCollisionResult?> showImportNameCollisionDialog(
  BuildContext context, {
  required String cardName,
  required List<CharacterCard> existing,
}) {
  assert(existing.isNotEmpty);
  return showDialog<ImportNameCollisionResult>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ImportNameCollisionDialog(
      cardName: cardName,
      existing: existing,
    ),
  );
}

/// Single-file import with Keep both / Replace / Cancel when the card's
/// display name already exists and stableId does not match a library entry.
/// Bulk paths should call [CharacterRepository.importCharacter] directly
/// (always keep both).
Future<CharacterCard?> importCharacterWithNameCollision(
  BuildContext context,
  CharacterRepository repo,
  File file,
) async {
  final isJson = file.path.toLowerCase().endsWith('.json');
  final v2 = V2CardService();
  final peeked = isJson
      ? await v2.readCardFromJsonFile(file.path)
      : await v2.readCard(file.path);
  final name = peeked?.name ?? p.basenameWithoutExtension(file.path);
  final stableId = peeked?.frontPorchExtensions?.stableId;

  // stableId match → silent update-in-place (history-preserving reimport).
  if (repo.findByStableId(stableId) != null) {
    return repo.importCharacter(file);
  }

  final existing = repo.charactersWithName(name);
  if (existing.isEmpty) {
    return repo.importCharacter(file);
  }

  if (!context.mounted) return null;
  final choice = await showImportNameCollisionDialog(
    context,
    cardName: name,
    existing: existing,
  );
  if (choice == null) return null; // cancel
  if (choice.keepBoth) {
    return repo.importCharacter(file);
  }
  return repo.importCharacter(
    file,
    forceReplaceTarget: choice.replaceTarget,
  );
}

class _ImportNameCollisionDialog extends StatefulWidget {
  final String cardName;
  final List<CharacterCard> existing;

  const _ImportNameCollisionDialog({
    required this.cardName,
    required this.existing,
  });

  @override
  State<_ImportNameCollisionDialog> createState() =>
      _ImportNameCollisionDialogState();
}

class _ImportNameCollisionDialogState extends State<_ImportNameCollisionDialog> {
  late String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.existing.first.dbId;
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.existing.length > 1;
    final accent = AppColors.porchAmberOf(context);

    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.5)),
      ),
      title: Row(
        children: [
          Icon(Icons.person_outline, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Character already exists',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WarmDialogText(
              multi
                  ? 'You already have ${widget.existing.length} characters named '
                      '"${widget.cardName}". Keep both (add another), or replace '
                      'one of the existing cards. Replacing keeps that card\'s '
                      'chat history.'
                  : 'You already have a character named "${widget.cardName}". '
                      'Keep both (add another copy), or replace the existing '
                      'card and keep its chat history.',
            ),
            if (multi) ...[
              const SizedBox(height: 12),
              Text(
                'Replace which one?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.existing.length,
                  itemBuilder: (context, i) {
                    final c = widget.existing[i];
                    final id = c.dbId ?? 'idx-$i';
                    final selected = id == _selectedId;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: accent.withValues(alpha: 0.12),
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? accent
                            : AppColors.iconSecondary(context),
                        size: 20,
                      ),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        id.length > 12
                            ? 'id …${id.substring(id.length - 8)}'
                            : id,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => setState(() => _selectedId = id),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        warmDialogCancel(context),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const ImportNameCollisionResult.keepBoth(),
          ),
          child: Text(
            'Keep both',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: AppColors.onChaosAccent,
          ),
          onPressed: () {
            CharacterCard? target;
            for (final c in widget.existing) {
              final id = c.dbId;
              if (id != null && id == _selectedId) {
                target = c;
                break;
              }
            }
            target ??= widget.existing.first;
            Navigator.of(context).pop(
              ImportNameCollisionResult.replace(target),
            );
          },
          child: const Text('Replace existing'),
        ),
      ],
    );
  }
}
