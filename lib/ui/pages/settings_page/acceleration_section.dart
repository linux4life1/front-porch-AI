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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Acceleration in Advanced Launch Options.
///
/// Acceleration is always worked out from the card (CUDA on NVIDIA, Metal
/// on a Mac, Vulkan on AMD or Intel). The one choice left is ROCm, which
/// is never picked by itself: a switch on an AMD card.
class AccelerationSection extends StatelessWidget {
  const AccelerationSection({
    super.key,
    required this.hardwareService,
    required this.onRocmChanged,
  });

  final HardwareService hardwareService;

  /// Called after the ROCm switch saves, so the owner rebuilds.
  final VoidCallback onRocmChanged;

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final bs = storage.backendSettings;
    final hw = hardwareService.hardwareInfo;
    final rocm = bs.useRocm == true;
    final backend = GpuBackendResolver.resolve(
      userCublas: bs.useCublas,
      userVulkan: bs.useVulkan,
      userRocm: bs.useRocm,
      userMetal: bs.useMetal,
      hasCuda: hw?.hasCuda ?? false,
      vendor: hw?.vendor ?? 'Unknown',
      // Detection reports Metal on every Mac and nowhere else.
      onMac: hw?.hasMetal,
    );
    final amd = hw?.vendor == 'AMD';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome,
              size: 16,
              color: AppColors.porchAmberOf(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                rocm
                    ? 'Acceleration: ROCm (AMD)'
                    : 'Acceleration: Automatic — '
                          '${GpuBackendResolver.describe(backend, hw?.vendor ?? 'Unknown')}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ],
        ),
        if (amd || rocm) _buildRocmRow(context, hw, rocm),
      ],
    );
  }

  /// "Use ROCm instead of Vulkan" on an AMD card. Off is automatic again.
  Widget _buildRocmRow(BuildContext context, HardwareInfo? hw, bool on) {
    final bs = Provider.of<StorageService>(
      context,
      listen: false,
    ).backendSettings;
    final offered = hw?.hasRocm == true;
    return Row(
      children: [
        Expanded(
          child: Text(
            offered
                ? 'Use ROCm instead of Vulkan (its engine downloads when '
                      'switched on)'
                : 'ROCm needs a Linux driver that offers it',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary(context),
            ),
          ),
        ),
        // Only where something can be done: an AMD card on Linux whose
        // driver offers no ROCm, or one this account may not use yet.
        if (hw != null && Platform.isLinux && (!hw.hasRocm || !hw.rocmAccess))
          TextButton(
            onPressed: () =>
                showRocmHelpDialog(context, driverReady: hw.hasRocm),
            child: const Text('Why can\'t I use ROCm?'),
          ),
        Switch(
          key: const ValueKey('use-rocm-switch'),
          value: on,
          activeTrackColor: AppColors.porchAmberOf(context),
          // Left on from before with no ROCm now, it can still be turned off.
          onChanged: offered || on
              ? (val) async {
                  // The driver offers it but this account may not use it:
                  // say how, rather than pick something that cannot run.
                  if (val && !hw!.rocmAccess) {
                    showRocmHelpDialog(context, driverReady: true);
                    return;
                  }
                  await bs.setUseRocm(val ? true : null);
                  onRocmChanged();
                }
              : null,
        ),
      ],
    );
  }
}
