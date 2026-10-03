// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Settings are read for every frame of a pack, so they stay fixed while busy.
class StudioSettingsGate extends StatelessWidget {
  const StudioSettingsGate({
    super.key,
    required this.busy,
    required this.child,
  });

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (busy)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Generation settings are locked while images are being made. You can keep editing your drafts.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
      Semantics(
        enabled: !busy,
        child: ExcludeFocus(
          excluding: busy,
          child: IgnorePointer(ignoring: busy, child: child),
        ),
      ),
    ],
  );
}

bool studioSettingsLocked(BuildContext context) =>
    context.read<ImageGenService?>()?.isGenerating ?? false;
