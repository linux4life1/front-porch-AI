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
import 'package:flutter/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The command that lets this account use the graphics card for ROCm.
const kRocmGroupCommand = r'sudo usermod -aG render,video $USER';

/// Why ROCm cannot run on this AMD card yet, and the one thing to do. Only
/// for the two cases where something can be done: the graphics driver does
/// not offer compute at all ([driverReady] false), or it does and this
/// account may not use it. KoboldCpp's ROCm build brings its own ROCm, so
/// nothing else needs installing.
Future<void> showRocmHelpDialog(
  BuildContext context, {
  required bool driverReady,
}) {
  return showWarmDialog<void>(
    context,
    icon: Icons.memory,
    accent: AppColors.porchAmberOf(context),
    width: 440,
    title: driverReady
        ? 'One step before ROCm works'
        : 'ROCm isn\'t available on this computer',
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: driverReady
            ? [
                const WarmDialogText(
                  'Your graphics card is ready, but your account isn\'t '
                  'allowed to use it for ROCm yet. Run this once in a '
                  'terminal, then log out and back in:',
                ),
                const SizedBox(height: 12),
                const _Command(kRocmGroupCommand),
                const SizedBox(height: 12),
                const WarmDialogText(
                  'Until then the app uses Vulkan, which works on every AMD '
                  'card.',
                ),
              ]
            : const [
                WarmDialogText(
                  'Your graphics driver isn\'t offering the part ROCm needs. '
                  'This usually means the system is older than the graphics '
                  'card, or the card is too old for ROCm.',
                ),
                SizedBox(height: 12),
                WarmDialogText(
                  'What to do: install your system\'s updates and restart. '
                  'Until then the app uses Vulkan, which works on every AMD '
                  'card.',
                ),
              ],
      ),
    ),
    actions: [
      if (driverReady)
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: kRocmGroupCommand));
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Command copied')));
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy command'),
        ),
      Builder(builder: (ctx) => warmDialogCancel(ctx, label: 'Got it')),
    ],
  );
}

class _Command extends StatelessWidget {
  const _Command(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}
