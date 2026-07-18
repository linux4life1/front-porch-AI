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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Warm-porch warning banner shown when this machine can only run local models
/// on the CPU, slowly (no AVX2 + no NVIDIA GPU — see
/// [HardwareService.cpuOnlyLowPerf]). Renders nothing on capable machines, so it
/// is safe to drop into any backend/setup surface unconditionally.
class LowPerfCpuWarning extends StatelessWidget {
  const LowPerfCpuWarning({super.key, this.margin});

  /// Optional outer margin so callers control spacing in their layout.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final lowPerf = context.select<HardwareService, bool>(
      (h) => h.cpuOnlyLowPerf,
    );
    if (!lowPerf) return const SizedBox.shrink();

    final accent = AppColors.porchAmberOf(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slow performance expected on this PC',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Your CPU doesn't support AVX2 and no NVIDIA GPU was found, so "
                  'the local AI runs on the CPU only — AMD/Intel graphics '
                  "can't be used by the compatible engine build. Replies may be "
                  'very slow. A newer CPU or an NVIDIA GPU is recommended, or '
                  'connect to a cloud model instead.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
