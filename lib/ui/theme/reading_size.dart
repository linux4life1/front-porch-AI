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

/// Base font size for reading surfaces: chat bubbles, the composer, and the
/// message editor. Never also multiply this by the Reading Size pref —
/// [readingTextScaler] / [ReadingSizeScope] is the only multiplier.
const double kReadingFontSize = 14.0;

/// Inclusive range for the Reading Size slider (General Settings and the
/// in-chat UI sheet share this).
const double kReadingScaleMin = 0.7;
const double kReadingScaleMax = 2.0;

/// The Reading Size pref as a [TextScaler]. One value for every reading
/// surface. Ambient MediaQuery can sit at 1.0 while this is 2.0.
TextScaler readingTextScaler(double textScale) =>
    TextScaler.linear(textScale.clamp(kReadingScaleMin, kReadingScaleMax));

/// Pushes Reading Size onto [child] as MediaQuery.textScaler so [Text] and
/// [TextField] inherit it. [RichText] still needs [readingTextScaler]
/// passed explicitly — Flutter defaults that widget to noScaling.
class ReadingSizeScope extends StatelessWidget {
  const ReadingSizeScope({
    super.key,
    required this.textScale,
    required this.child,
  });

  final double textScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: readingTextScaler(textScale)),
      child: child,
    );
  }
}

/// Sidebar helper / journal preview copy. Contrast is primary text,
/// not a faint secondary.
const double kSidebarHelpFontSize = 13.0;

/// Shared prose style for reading surfaces. Callers add color / height / italic
/// but not a second scale factor.
TextStyle readingSurfaceStyle({
  required Color color,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? height,
}) {
  return TextStyle(
    color: color,
    fontSize: kReadingFontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    height: height,
  );
}
