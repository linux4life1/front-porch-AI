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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

String callStatusText(CallStatus status) => switch (status) {
  CallStatus.listening => 'Listening…',
  CallStatus.transcribing => 'Transcribing…',
  CallStatus.thinking => 'Thinking…',
  CallStatus.speaking => 'Speaking…',
  CallStatus.idle => 'Calibrating…',
};

IconData callStatusIcon(CallStatus status) => switch (status) {
  CallStatus.listening => Icons.mic,
  CallStatus.transcribing => Icons.text_fields,
  CallStatus.thinking => Icons.psychology,
  CallStatus.speaking => Icons.volume_up,
  CallStatus.idle => Icons.pause,
};

Color callStatusColor(BuildContext context, CallStatus status) =>
    switch (status) {
      CallStatus.listening => AppColors.porchAmberOf(context),
      CallStatus.transcribing => AppColors.porchHoneyOf(context),
      CallStatus.thinking => AppColors.textSecondary(context),
      CallStatus.speaking => AppColors.porchTerracottaOf(context),
      CallStatus.idle => AppColors.textTertiary(context),
    };

/// The pill under the name saying what the call is doing right now.
class CallStatusChip extends StatelessWidget {
  const CallStatusChip({super.key, required this.status});

  final CallStatus status;

  @override
  Widget build(BuildContext context) {
    final color = callStatusColor(context, status);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey(status),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(callStatusIcon(status), size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              callStatusText(status),
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
