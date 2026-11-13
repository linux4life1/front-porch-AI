// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/app_corners.dart';

/// A card container that groups related settings rows together.
///
/// Features a unified rounded border, theme-aware card background,
/// and optional subtle hairline dividers between consecutive child items.
class SettingsGroupCard extends StatelessWidget {
  const SettingsGroupCard({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.showDividers = true,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderOf(context);
    final dividerColor = borderColor.withValues(alpha: 0.5);
    final borderRadius = AppCorners.of(context).circular(12);

    List<Widget> content;
    if (showDividers && children.length > 1) {
      content = [];
      for (var i = 0; i < children.length; i++) {
        content.add(children[i]);
        if (i < children.length - 1) {
          content.add(
            Divider(
              height: 1,
              thickness: 1,
              color: dividerColor,
            ),
          );
        }
      }
    } else {
      content = children;
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
        ),
      ),
    );
  }
}
