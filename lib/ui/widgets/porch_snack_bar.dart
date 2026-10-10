// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A success toast on the porch surface: [message] in the theme's primary
/// ink beside an amber check, so it reads in light and dark mode.
///
/// Use it instead of a bare `SnackBar` whenever you give the toast a light
/// surface colour: the default snackbar text is pale ink meant for Material's
/// inverted (dark) background and vanishes on paper.
SnackBar porchSnackBar(BuildContext context, String message) => SnackBar(
  content: Row(
    children: [
      Icon(
        Icons.check_circle,
        color: AppColors.porchAmberOf(context),
        size: 20,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
  backgroundColor: AppColors.surfaceContainerOf(context),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
    side: BorderSide(color: AppColors.borderOf(context)),
  ),
  behavior: SnackBarBehavior.floating,
);
