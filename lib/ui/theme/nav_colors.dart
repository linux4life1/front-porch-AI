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

import 'app_colors.dart';

/// Hues for the sidebar's flagship destinations and outside links. Each
/// destination keeps its own hue in every app theme; light mode deepens it
/// so it reads on paper.
class NavColors {
  NavColors._();

  /// The Stoop.
  static Color stoopOf(BuildContext context) =>
      AppColors.resolve(context, Colors.tealAccent, const Color(0xFF00695C));
  static Color stoopWashOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.tealAccent.withValues(alpha: 0.08),
    Colors.teal.withValues(alpha: 0.10),
  );

  /// The AI Character Creator, and its randomize dice.
  static Color creatorOf(BuildContext context) =>
      AppColors.resolve(context, Colors.amberAccent, const Color(0xFF92400E));
  static final Color creatorWash = Colors.amber.withValues(alpha: 0.08);

  /// Create Group Chat.
  static const Color groupChat = Color(0xFF7C3AED);
  static final Color groupChatWash = groupChat.withValues(alpha: 0.08);

  /// Brand marks on the community links.
  static const Color discord = Color(0xFF5865F2);
  static const Color kofi = Color(0xFFFF5E5B);
}
