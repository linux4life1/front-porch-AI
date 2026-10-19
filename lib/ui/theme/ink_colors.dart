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

/// Neutral ink that is not part of a palette: dims over content, faint
/// lines and wells that read on both dark and light grounds.
class InkColors {
  InkColors._();

  /// A darkening layer: modal dims, wells, scrims over pictures. Black in
  /// every theme, because it only has to push what is under it back.
  static Color dim(double alpha) => Colors.black.withValues(alpha: alpha);

  /// Text and icons laid over a picture or a dim.
  static const Color onImage = Colors.white;

  /// The faint border around chip rows and pills.
  static Color faintLineOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white10,
    Colors.black.withValues(alpha: 0.09),
  );

  /// The hairline border around tooltips and soft buttons.
  static Color lineOf(BuildContext context) => AppColors.resolve(
    context,
    Colors.white12,
    Colors.black.withValues(alpha: 0.11),
  );

  /// The well behind a realism chip row. Light mode backs it with the card,
  /// because a chat theme can put a dark bubble under it in either mode and
  /// light-mode chip inks are deep tones. [dark] keeps each row's dim.
  static Color chipWellOf(
    BuildContext context, {
    Color dark = Colors.black12,
  }) => AppColors.resolve(context, dark, AppColors.cardOf(context));

  /// A drag grip on a resizable edge.
  static Color gripOf(BuildContext context) =>
      AppColors.resolve(context, Colors.white24, Colors.black12);
}
