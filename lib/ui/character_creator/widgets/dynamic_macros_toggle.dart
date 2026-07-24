// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Opt-in "Dynamic macros" toggle, shared across the Quick / Guided / Automated
/// creator config steps so the choice is a config-time decision in EVERY mode.
///
/// Controls whether the generator invites the model to add `{{pick}}`/`{{roll}}`
/// "living detail" macros to world lore + the opening message. Presentational
/// only — the parent owns the state field and its save.
class DynamicMacrosToggle extends StatelessWidget {
  const DynamicMacrosToggle({
    super.key,
    required this.value,
    required this.accentColor,
    required this.onChanged,
  });

  final bool value;
  final Color accentColor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.casino_outlined, color: accentColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'Dynamic macros',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message:
                    'Lets the AI sprinkle {{pick:…}} and {{roll:…}} macros into '
                    'world lore and the opening message, so small details vary '
                    'each playthrough — a tavern\'s daily special, a passing '
                    'sound, a random count. Off by default: capable models use '
                    'them well; smaller models may place them awkwardly or skip '
                    'them.',
                child: Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeTrackColor: accentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
