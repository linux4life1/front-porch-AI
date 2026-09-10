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
import 'package:front_porch_ai/ui/waifu/waifu_honesty_text.dart';

Future<bool> showWaifuWholeDiskHonesty(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const WaifuWholeDiskHonestyDialog(),
      ) ??
      false;
}

/// Whole-disk is a real upgrade. Jail does not need this.
class WaifuWholeDiskHonestyDialog extends StatefulWidget {
  const WaifuWholeDiskHonestyDialog({super.key});

  @override
  State<WaifuWholeDiskHonestyDialog> createState() =>
      _WaifuWholeDiskHonestyDialogState();
}

class _WaifuWholeDiskHonestyDialogState
    extends State<WaifuWholeDiskHonestyDialog> {
  var _accepted = false;

  @override
  Widget build(BuildContext context) {
    const scope = WaifuPathMode.wholeDisk;
    final amber = AppColors.porchAmberOf(context);
    return AlertDialog(
      key: const Key('waifu-whole-disk-honesty'),
      backgroundColor: AppColors.cardOf(context),
      title: Text(
        waifuPathModeTitle(scope),
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WaifuHonestyText(text: waifuHonestyBody(scope)),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('waifu-whole-disk-honesty-check'),
                value: _accepted,
                onChanged: (v) => setState(() => _accepted = v ?? false),
                title: Text(waifuHonestyCheckbox(scope)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('waifu-whole-disk-honesty-cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Stay in jail',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton(
          key: const Key('waifu-whole-disk-honesty-confirm'),
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
            disabledBackgroundColor: AppColors.surfaceContainerOf(context),
          ),
          child: const Text('Open the disk'),
        ),
      ],
    );
  }
}
