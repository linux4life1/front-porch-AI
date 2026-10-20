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

import 'app_colors.dart';

/// Download queue status hues, one per task state. The consts are the dark
/// tones; each *Light const deepens them in light mode so the status line reads on paper.
class DownloadStatusColors {
  DownloadStatusColors._();

  static const Color downloading = Color(0xFF40C4FF);
  static const Color paused = Color(0xFFFFD54F);
  static const Color pending = Color(0xFF9CA3AF);
  static const Color completed = Color(0xFF69F0AE);
  static const Color failed = Color(0xFFFF5252);
  static const Color verifying = Color(0xFFB388FF);
  static const Color cancelled = Color(0xFF6B7280);

  static const Color downloadingLight = Color(0xFF075985);
  static const Color pausedLight = Color(0xFF92400E);
  static const Color pendingLight = Color(0xFF4B5563);
  static const Color completedLight = Color(0xFF1B5E20);
  static const Color failedLight = Color(0xFFB71C1C);
  static const Color verifyingLight = Color(0xFF6D28D9);
  static const Color cancelledLight = Color(0xFF4B5563);

  /// The running download's hue in the current mode.
  static Color downloadingOf(BuildContext context) =>
      AppColors.resolve(context, downloading, downloadingLight);
}
