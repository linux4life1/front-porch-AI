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

import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Sit-down honesty body with closed `**…**` rendered as weight, not sludge.
class WaifuHonestyText extends StatelessWidget {
  const WaifuHonestyText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      color: AppColors.textPrimary(context),
      height: 1.4,
    );
    final spans = waifuEmphasisSpans(text);
    return Text.rich(
      key: const Key('waifu-honesty-body'),
      TextSpan(
        style: base,
        children: [
          for (final s in spans)
            TextSpan(
              text: s.text,
              style: s.bold
                  ? const TextStyle(fontWeight: FontWeight.w800)
                  : null,
            ),
        ],
      ),
    );
  }
}
