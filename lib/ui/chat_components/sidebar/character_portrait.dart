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

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Square character portrait used by Chat and Waifu Coder.
///
/// ChatPage still decides *which* file (expressions / gallery ring). This
/// widget is the pixels: cover image, person fallback, optional overlays
/// (emotion badge, look chevrons).
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.size,
    this.file,
    this.imageKey = 'default',
    this.overlays = const [],
    this.alignEnd = false,
    this.shrinkIfEmpty = true,
  });

  final File? file;
  final double size;
  final String imageKey;
  final List<Widget> overlays;
  final bool alignEnd;

  /// Chat's expression-off empty path returns nothing. Waifu Coder passes
  /// false so a card without a portrait still shows a person tile.
  final bool shrinkIfEmpty;

  @override
  Widget build(BuildContext context) {
    final display = file;
    if (display == null && shrinkIfEmpty) return const SizedBox.shrink();

    Widget avatar = SizedBox(
      height: size,
      width: size,
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            child: display == null
                ? _fallback(context)
                : Image.file(
                    display,
                    key: ValueKey(imageKey),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, _, _) => _fallback(context),
                  ),
          ),
          ...overlays,
        ],
      ),
    );
    if (alignEnd) {
      avatar = Align(alignment: Alignment.topRight, child: avatar);
    }
    return avatar;
  }

  Widget _fallback(BuildContext context) {
    return Container(
      key: const ValueKey('portrait-fallback'),
      width: size,
      height: size,
      color: AppColors.resolve(
        context,
        Colors.black26,
        Colors.black.withValues(alpha: 0.1),
      ),
      child: Icon(
        Icons.person,
        color: AppColors.iconSecondary(context),
        size: size * 0.45,
      ),
    );
  }
}
