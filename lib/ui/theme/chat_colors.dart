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

/// Chat-screen hues with one job each: the thinking panel, Director notes,
/// the generation status bar, Memory setup and the message action icons.
/// Per brightness only; dark keeps the colors the chat always showed.
class ChatColors {
  ChatColors._();

  /// The panel that shows a reply's thinking, and its "Thought" chip.
  static Color thoughtPanelOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF1A2A3A),
    const Color(0xFFE0F2FE),
  );
  static Color thoughtChipOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF2A4A5A),
    const Color(0xFFE0F2FE),
  );
  static Color thoughtInkOf(BuildContext context) =>
      AppColors.resolve(context, Colors.tealAccent, const Color(0xFF00695C));

  /// Director notes in the transcript.
  static Color directorOf(BuildContext context) => AppColors.resolve(
    context,
    AppColors.chaosAccent,
    const Color(0xFF92400E),
  );

  /// A warm notice panel inside the composer.
  static Color noticePanelOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF3A2E14),
    const Color(0xFFFDF3D7),
  );

  /// Memory (RAG) setup.
  static Color memoryOf(BuildContext context) =>
      AppColors.resolve(context, Colors.purpleAccent, const Color(0xFF7B1FA2));
  static const Color memoryDeep = Colors.deepPurple;

  /// Regenerate and the greeting counter.
  static Color regenOf(BuildContext context) =>
      AppColors.resolve(context, Colors.orangeAccent, const Color(0xFF9A3412));

  /// Continue generation.
  static Color continueOf(BuildContext context) =>
      AppColors.resolve(context, Colors.blue, const Color(0xFF1D4ED8));

  /// The swipe counter.
  static Color swipeOf(BuildContext context) =>
      AppColors.resolve(context, Colors.greenAccent, const Color(0xFF1B5E20));

  /// A portrait placeholder when a group member has no avatar.
  static const Color avatarFallback = Colors.purple;

  // Generation status bar phases.
  static Color preparingOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFF59E0B),
    const Color(0xFF92400E),
  );
  static Color prefillingOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFF97316),
    const Color(0xFF9A3412),
  );
  static Color thinkingOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFA855F7),
    const Color(0xFF6D28D9),
  );
  static Color bufferingOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF3B82F6),
    const Color(0xFF1D4ED8),
  );
  static Color generatingOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF10B981),
    const Color(0xFF065F46),
  );
  static Color speedOf(BuildContext context) =>
      AppColors.resolve(context, Colors.amberAccent, const Color(0xFF92400E));

  /// One hue per group member, by seat: avatars, roster rings, accents.
  static const List<Color> groupMembers = [
    Color(0xFF8B5CF6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFF97316),
  ];
}
