// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_tag_selector.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Upload wizard step 1 — name, summary, original creator, tags.
class StoopUploadDetailsStep extends StatelessWidget {
  /// The picked character's in-chat name, or null for a group / place.
  final String? selectedCharacterName;
  final TextEditingController name;
  final TextEditingController summary;
  final TextEditingController originalCreator;
  final TextEditingController tagInput;
  final List<String> tagPool;
  final List<String> tags;
  final int maxTags;

  /// Any field edit (the owner rebuilds so Next re-validates).
  final VoidCallback onChanged;
  final ValueChanged<String> onToggleTag;
  final ValueChanged<String> onAddTag;

  const StoopUploadDetailsStep({
    super.key,
    required this.selectedCharacterName,
    required this.name,
    required this.summary,
    required this.originalCreator,
    required this.tagInput,
    required this.tagPool,
    required this.tags,
    required this.maxTags,
    required this.onChanged,
    required this.onToggleTag,
    required this.onAddTag,
  });

  @override
  Widget build(BuildContext context) {
    InputDecoration input(String hint) => stoopInput(context, hint);
    return ListView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.all(24),
      children: [
        _label(context, 'Display name on The Stoop'),
        TextField(
          controller: name,
          onChanged: (_) => onChanged(),
          style: TextStyle(color: stoopCream(context)),
          decoration: input('Name shown on The Stoop'),
        ),
        const SizedBox(height: 8),
        // Unmissable: this box is the LISTING title, not the chat name.
        // {{char}} keeps mapping to the card's own name, which never changes
        // here — so "Misty Meadows, Misguided Meteorologist" is safe.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: stoopAmberSoft(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.stoopAmber.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: stoopAmberText(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedCharacterName != null
                      ? 'This is the display name for the listing only — not '
                            'the chat name. In chat, {{char}} still maps to '
                            '“$selectedCharacterName”, so replies keep calling '
                            'them “$selectedCharacterName” no matter what you '
                            'title the post.'
                      : 'This is the display name for the listing only — in '
                            'chat, everyone keeps their own name no matter '
                            'what you title the post.',
                  style: TextStyle(
                    color: stoopCream2(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _label(context, 'Short summary'),
        TextField(
          controller: summary,
          maxLines: 3,
          maxLength: 280,
          onChanged: (_) => onChanged(),
          style: TextStyle(color: stoopCream(context)),
          decoration: input('A one-line hook shown on the card'),
        ),
        const SizedBox(height: 18),
        _label(context, 'Original creator (optional)'),
        TextField(
          controller: originalCreator,
          maxLength: 120,
          onChanged: (_) => onChanged(),
          style: TextStyle(color: stoopCream(context)),
          decoration: input('Leave blank if this is your own work').copyWith(
            counterText: '',
            helperText:
                'Sharing someone else’s character? Credit them here — the '
                'card will show “created by …”. The AUP requires this for '
                'reposts; they don’t need a Stoop account.',
            helperMaxLines: 3,
            helperStyle: TextStyle(color: stoopMute(context), fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        StoopTagSelector(
          pool: tagPool,
          selected: tags,
          max: maxTags,
          controller: tagInput,
          decorate: input,
          onToggle: onToggleTag,
          onAdd: onAddTag,
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: stoopCream2(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
