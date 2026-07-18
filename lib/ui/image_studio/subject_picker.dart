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
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Subject selector for the Image Studio: what the image is *of*.
///
/// The three subjects map onto the surviving [ImageGenMode]s:
/// - **Freeform** → `customPrompt` (type anything; blank + Craft pictures the scene)
/// - **Character** → `characterPortrait` (a chat character's appearance)
/// - **Your persona** → `userAvatar` (the user persona's appearance)
///
/// In a **group** chat there is no single active character, so the Character
/// button opens a picker of the cast — you portrait one member at a time
/// (reliable), rather than trying to render multiple specific characters in one
/// image (which vanilla diffusion does poorly).
class SubjectPicker extends StatelessWidget {
  final ImageGenMode selected;

  /// The active character's name (1:1 chat) or the currently-picked group
  /// member. When null/empty AND there are no [groupCharacters], the Character
  /// option is disabled (nothing to portray).
  final String? characterName;

  /// In a group chat, the cast to choose from. When non-empty, the Character
  /// button opens a member picker instead of selecting directly.
  final List<({String name, String description, String? dbId})>
  groupCharacters;

  final ValueChanged<ImageGenMode>? onChanged;

  /// Fires with the chosen index into [groupCharacters] when a group member is
  /// picked for a portrait.
  final ValueChanged<int>? onPickGroupMember;

  /// Fires when "Group shot" is chosen — attempt the whole cast in one image
  /// (honestly caveated: diffusion models render multiple specific characters
  /// unreliably).
  final VoidCallback? onPickGroupShot;

  const SubjectPicker({
    super.key,
    required this.selected,
    required this.characterName,
    required this.onChanged,
    this.groupCharacters = const [],
    this.onPickGroupMember,
    this.onPickGroupShot,
  });

  @override
  Widget build(BuildContext context) {
    final hasGroup = groupCharacters.isNotEmpty;
    final hasCharacter = (characterName ?? '').trim().isNotEmpty;
    final characterEnabled = onChanged != null && (hasCharacter || hasGroup);
    final characterLabel = hasCharacter
        ? characterName!.trim()
        : (hasGroup ? 'Character…' : 'Character');

    // (mode, label, icon, enabled, onTap)
    final options = <(ImageGenMode, String, IconData, bool, VoidCallback?)>[
      (
        ImageGenMode.customPrompt,
        'Freeform',
        Icons.brush,
        onChanged != null,
        onChanged == null ? null : () => onChanged!(ImageGenMode.customPrompt),
      ),
      (
        ImageGenMode.characterPortrait,
        characterLabel,
        Icons.face,
        characterEnabled,
        !characterEnabled
            ? null
            : (hasGroup
                  ? () => _showMemberMenu(context)
                  : () => onChanged!(ImageGenMode.characterPortrait)),
      ),
      (
        ImageGenMode.userAvatar,
        'Your persona',
        Icons.person,
        onChanged != null,
        onChanged == null ? null : () => onChanged!(ImageGenMode.userAvatar),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subject',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((o) {
            final (mode, label, icon, enabled, onTap) = o;
            final isSel = mode == selected;
            final accent = AppColors.formMasterAccent;
            return OutlinedButton.icon(
              onPressed: enabled ? onTap : null,
              icon: Icon(
                icon,
                size: 16,
                color: isSel ? accent : AppColors.iconSecondary(context),
              ),
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSel
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                side: BorderSide(
                  color: isSel ? accent : AppColors.borderOf(context),
                ),
                backgroundColor: isSel ? AppColors.cardOf(context) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Pop a menu of the group cast anchored to the Character button; the chosen
  /// member becomes the portrait subject.
  Future<void> _showMemberMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final idx = await showMenu<int>(
      context: context,
      position: pos,
      color: AppColors.surfaceContainerOf(context),
      items: [
        // Whole-cast shot (value -1) — first, with the honest caveat inline.
        PopupMenuItem<int>(
          value: -1,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Group shot — all ${groupCharacters.length}',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'results vary by model',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (var i = 0; i < groupCharacters.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              groupCharacters[i].name,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
          ),
      ],
    );
    if (idx == null) return;
    if (idx < 0) {
      onPickGroupShot?.call();
    } else {
      onPickGroupMember?.call(idx);
    }
  }
}
