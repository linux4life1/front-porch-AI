// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "`name` created successfully!" after either character creator finishes.
/// Text in the theme's primary ink on the porch surface with an amber check,
/// so it reads in light and dark mode (the default snackbar text is dark ink
/// meant for an inverted background).
SnackBar characterCreatedSnackBar(BuildContext context, String name) =>
    SnackBar(
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
              '$name created successfully!',
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
