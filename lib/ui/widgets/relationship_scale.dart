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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Hidden intragroup relationship tier name for a raw -300..+300 feeling score.
/// Aligned with the Long-Term Bond tiers used in the 1:1 Realism creator and
/// runtime evaluations. Shared by the group creator's Dynamics step and the
/// post-creation group editor so both label the same score identically.
String relationshipTierName(int value) {
  if (value >= 80) return 'Soulbound';
  if (value >= 50) return 'Deep Bond';
  if (value >= 20) return 'Close';
  if (value >= 5) return 'Familiar';
  if (value >= -4) return 'Acquaintance';
  if (value >= -19) return 'Uneasy';
  if (value >= -49) return 'Estranged';
  if (value >= -79) return 'Broken';
  return 'Nemesis';
}

/// Granular valence color (green = positive, red = negative) for an intragroup
/// feeling score. Shared with the group creator so the two surfaces color the
/// same value identically (thresholds match the tier boundaries).
Color relationshipScaleColor(BuildContext context, int value) {
  if (value >= 80) {
    return AppColors.resolve(
      context,
      Colors.greenAccent.shade200,
      Colors.green.shade200,
    );
  } else if (value >= 50) {
    return AppColors.resolve(
      context,
      Colors.greenAccent.shade400,
      Colors.green.shade400,
    );
  } else if (value >= 20) {
    return AppColors.resolve(
      context,
      Colors.greenAccent.shade700,
      Colors.green.shade700,
    );
  } else if (value >= 5) {
    return AppColors.resolve(context, Colors.lightGreen, Colors.lightGreen);
  } else if (value >= -4) {
    return AppColors.textSecondary(context);
  } else if (value >= -19) {
    return AppColors.resolve(context, Colors.orangeAccent, Colors.orange.shade700);
  } else if (value >= -49) {
    return AppColors.resolve(
      context,
      Colors.deepOrangeAccent,
      Colors.deepOrange.shade700,
    );
  } else if (value >= -79) {
    return AppColors.resolve(context, Colors.redAccent, Colors.red.shade700);
  } else {
    return AppColors.resolve(context, Colors.red.shade700, Colors.red.shade900);
  }
}
