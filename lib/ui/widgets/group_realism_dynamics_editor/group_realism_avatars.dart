// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import 'group_realism_member.dart';

/// Member avatars for the group realism editor, with the per-editor
/// existence cache.
class GroupRealismAvatars {
  // Memoized per editor: avatar runs once per member card, once per source
  // row and once per source×target pair, and EVERY relationship-slider drag
  // frame rebuilds the whole editor — N existsSync per frame is the io-lint
  // bug class (same shape as scene_guest_picker_dialog's cache).
  final Map<String, File?> _avatarCache = {};

  Widget avatar(BuildContext context, GroupRealismMember m, double radius) {
    final path = m.avatarPath;
    final file = (path == null || path.isEmpty)
        ? null
        : _avatarCache.putIfAbsent(
            path,
            () =>
                File(path)
                    .existsSync() // io-ok: memoized per editor
                ? File(path)
                : null,
          );
    // A member made without a portrait shows its initial, not its flat
    // card colour.
    return RealPortrait(
      file: file,
      portrait: (_, f) =>
          CircleAvatar(radius: radius, backgroundImage: FileImage(f)),
      noPortrait: (_) => CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.surfaceContainerOf(context),
        child: Text(
          m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
      ),
    );
  }
}
