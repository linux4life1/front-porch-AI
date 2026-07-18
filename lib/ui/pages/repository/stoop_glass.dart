// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

final MacroResolver _stoopMacros = MacroResolver();

/// Resolve `{{char}}` → the character's name (and `{{user}}` → "You") for any
/// card text shown in The Stoop, using the app's shared macro resolver so it
/// matches how definitions render in chat.
String stoopResolveMacros(String text, String charName) {
  if (text.isEmpty || !text.contains('{')) return text;
  return _stoopMacros.resolve(
    text,
    MacroContext(userName: 'You', characterName: charName),
  );
}

/// Compact label for a card's token count — `620` or `1.2k` (drops a trailing
/// `.0`). Returns null for a null/zero count so callers can hide the chip
/// (older records may not be backfilled yet).
String? stoopTokenLabel(int? tokens) {
  if (tokens == null || tokens <= 0) return null;
  if (tokens < 1000) return '$tokens';
  final s = (tokens / 1000).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}k';
}

/// The Stoop's signature accent (teal) and its teal→purple gradient — used for
/// glows, score badges, and the hero scrim. Built from AppColors.resolve so it
/// adapts to light/dark like the rest of the app.
Color stoopAccent(BuildContext context) =>
    AppColors.resolve(context, Colors.tealAccent, Colors.teal);

Color stoopAccent2(BuildContext context) =>
    AppColors.resolve(context, Colors.purpleAccent, Colors.purple);

LinearGradient stoopGradient(BuildContext context, {double opacity = 1}) =>
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        stoopAccent(context).withValues(alpha: opacity),
        stoopAccent2(context).withValues(alpha: opacity),
      ],
    );

/// A frosted-glass panel: a backdrop blur behind a translucent fill, a soft
/// theme border, and an optional accent glow. The reusable building block for
/// the cinematic Stoop (cards, hero, the detail panel).
class StoopGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final bool glow;
  final double fillOpacity;
  const StoopGlass({
    super.key,
    required this.child,
    this.radius = 16,
    this.blur = 16,
    this.padding,
    this.glow = false,
    this.fillOpacity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final border = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: glow
            ? [
                BoxShadow(
                  color: stoopAccent(context).withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: border,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(
                context,
              ).withValues(alpha: fillOpacity),
              borderRadius: border,
              border: Border.all(
                color: AppColors.borderOf(context).withValues(alpha: 0.6),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A small frosted pill (net score, NSFW, GROUP) with an optional accent tint.
class StoopPill extends StatelessWidget {
  final Widget child;
  final Color? tint;
  const StoopPill({super.key, required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (tint ?? Colors.black).withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (tint ?? Colors.white).withValues(alpha: 0.25),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
