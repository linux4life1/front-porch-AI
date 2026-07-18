// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// An avatar montage that adapts to the cast size so no blank slots are left:
/// 1 fills the square, 2 sit side-by-side (full height), 3 form an inverted
/// pyramid (two on top, one centered below), and 4+ use the iOS-style 2x2 grid.
///
/// Shared by the home grid (folder + group cards) and the Stoop share picker so
/// a group looks identical everywhere its members are previewed.
class GroupAvatarMontage extends StatelessWidget {
  /// The member/character avatar files, in display order. Up to four are shown.
  final List<File> images;

  /// The square side length the montage should fill.
  final double side;

  const GroupAvatarMontage({
    super.key,
    required this.images,
    required this.side,
  });

  Widget _cell(BuildContext context, File? img, double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(6),
      image: img != null
          ? DecorationImage(image: FileImage(img), fit: BoxFit.cover)
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    const gap = 3.0;
    final n = images.length;

    if (n <= 1) {
      return _cell(context, n == 1 ? images[0] : null, side, side);
    }

    final half = (side - gap) / 2;
    if (n == 2) {
      return SizedBox(
        width: side,
        height: side,
        child: Row(
          children: [
            _cell(context, images[0], half, side),
            const SizedBox(width: gap),
            _cell(context, images[1], half, side),
          ],
        ),
      );
    }
    if (n == 3) {
      return SizedBox(
        width: side,
        height: side,
        child: Column(
          children: [
            Row(
              children: [
                _cell(context, images[0], half, half),
                const SizedBox(width: gap),
                _cell(context, images[1], half, half),
              ],
            ),
            const SizedBox(height: gap),
            _cell(context, images[2], half, half), // centered by the Column
          ],
        ),
      );
    }
    // 4+ : 2x2 grid (any extra members aren't shown).
    Widget tile(int i) => _cell(context, i < n ? images[i] : null, half, half);
    Widget row(int a, int b) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [tile(a), const SizedBox(width: gap), tile(b)],
    );
    return SizedBox(
      width: side,
      height: side,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [row(0, 1), const SizedBox(height: gap), row(2, 3)],
      ),
    );
  }
}
