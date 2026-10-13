// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

class ExpressionIntensityPicker extends StatelessWidget {
  const ExpressionIntensityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.onFollowPack,
    this.followsPack = false,
  });
  final ExpressionIntensity value;
  final ValueChanged<ExpressionIntensity>? onChanged;
  final VoidCallback? onFollowPack;
  final bool followsPack;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Expression intensity',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expression intensity',
          style: TextStyle(color: AppColors.textPrimary(context)),
        ),
        DropdownButton<String>(
          value: followsPack && onFollowPack != null ? 'pack' : value.name,
          isExpanded: true,
          style: TextStyle(color: AppColors.textPrimary(context)),
          items: [
            if (onFollowPack != null)
              const DropdownMenuItem(value: 'pack', child: Text('Follow pack')),
            for (final level in ExpressionIntensity.values)
              DropdownMenuItem(value: level.name, child: Text(level.label)),
          ],
          onChanged: onChanged == null
              ? null
              : (choice) {
                  if (choice == 'pack') {
                    onFollowPack?.call();
                  } else if (choice != null) {
                    onChanged!(ExpressionIntensity.parse(choice));
                  }
                },
        ),
        Text(
          'Adjusts expression wording. Results depend on the model.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      ],
    ),
  );
}
