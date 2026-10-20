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

/// Model hues: quant quality, VRAM fit and memory use. Dark keeps the
/// Material A-tones the model cards always used; light takes deeper tones
/// that read on paper.
class ModelColors {
  ModelColors._();

  static Color redOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFFF5252),
    const Color(0xFFB71C1C),
  );
  static Color orangeOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFFFB74D),
    const Color(0xFF9A3412),
  );
  static Color yellowOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFFFD54F),
    const Color(0xFF854D0E),
  );
  static Color greenOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF69F0AE),
    const Color(0xFF1B5E20),
  );
  static Color blueOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFF40C4FF),
    const Color(0xFF075985),
  );
  static Color purpleOf(BuildContext context) => AppColors.resolve(
    context,
    const Color(0xFFB388FF),
    const Color(0xFF6D28D9),
  );
  static Color greyOf(BuildContext context) =>
      AppColors.resolve(context, Colors.grey, const Color(0xFF575757));

  /// A quant type's quality hue, by its colour category.
  static Color quantOf(BuildContext context, String category) =>
      switch (category) {
        'red' => redOf(context),
        'orange' => orangeOf(context),
        'yellow' => yellowOf(context),
        'green' => greenOf(context),
        'blue' => blueOf(context),
        'purple' => purpleOf(context),
        _ => greyOf(context),
      };
}
