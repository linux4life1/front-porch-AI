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

/// Download queue status hues, one per task state.
///
/// The bare constants are the dark-mode hues, kept for old callers. Paint
/// with the `*Of(context)` getters: in light mode they return a deep tone
/// that clears 4.5:1 on light paper (#F0EBE3) and on white.
class DownloadStatusColors {
  DownloadStatusColors._();

  static const Color downloading = Color(0xFF40C4FF);
  static const Color paused = Color(0xFFFFD54F);
  static const Color pending = Color(0xFF9CA3AF);
  static const Color completed = Color(0xFF69F0AE);
  static const Color failed = Color(0xFFFF5252);
  static const Color verifying = Color(0xFFB388FF);
  static const Color cancelled = Color(0xFF6B7280);

  static const Color _downloadingLight = Color(0xFF075985);
  static const Color _pausedLight = Color(0xFF92400E);
  static const Color _pendingLight = Color(0xFF4B5563);
  static const Color _completedLight = Color(0xFF1B5E20);
  static const Color _failedLight = Color(0xFFB71C1C);
  static const Color _verifyingLight = Color(0xFF6D28D9);
  static const Color _cancelledLight = Color(0xFF5C6370);

  static Color _pick(BuildContext context, Color dark, Color light) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;

  static Color downloadingOf(BuildContext context) =>
      _pick(context, downloading, _downloadingLight);
  static Color pausedOf(BuildContext context) =>
      _pick(context, paused, _pausedLight);
  static Color pendingOf(BuildContext context) =>
      _pick(context, pending, _pendingLight);
  static Color completedOf(BuildContext context) =>
      _pick(context, completed, _completedLight);
  static Color failedOf(BuildContext context) =>
      _pick(context, failed, _failedLight);
  static Color verifyingOf(BuildContext context) =>
      _pick(context, verifying, _verifyingLight);
  static Color cancelledOf(BuildContext context) =>
      _pick(context, cancelled, _cancelledLight);
}
