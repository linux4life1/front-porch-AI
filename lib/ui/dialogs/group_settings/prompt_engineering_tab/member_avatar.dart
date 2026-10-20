// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The member's portrait, or its initial when it has none (or only the
/// flat placeholder a character made without a portrait carries).
class GroupPromptMemberAvatar extends StatelessWidget {
  final CharacterCard character;
  final Color accent;

  const GroupPromptMemberAvatar({
    super.key,
    required this.character,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = character;
    return RealPortrait(
      file: c.imagePath != null ? File(c.imagePath!) : null,
      portrait: (_, file) => CircleAvatar(
        radius: 16,
        backgroundColor: accent,
        backgroundImage: FileImage(file),
      ),
      noPortrait: (_) => CircleAvatar(
        radius: 16,
        backgroundColor: accent,
        child: Text(
          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: StatusColors.onFill,
          ),
        ),
      ),
    );
  }
}
