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
import 'package:front_porch_ai/ui/theme/theme.dart';

const kChatThemeFontOptions = [
  'serif',
  'sans-serif',
  'monospace',
  'Georgia',
  'Times New Roman',
  'Arial',
  'Helvetica',
  'Courier New',
  'Verdana',
  'Roboto',
  'Open Sans',
  'Lato',
  'Merriweather',
  'Playfair Display',
  'Source Code Pro',
];

const kChatThemeBorderStyles = [
  'scalloped',
  'dualLine',
  'grid',
  'wavy',
  'shadow',
  'vine',
  'wave',
  'glitch',
  'floral',
  'gear',
  'greekKey',
];

/// A Chat Theme override row (Font, Border): label, a dropdown of [options]
/// showing [value], and — while [overridden] — a reset button.
class ChatThemeDropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;

  /// Style for each option's text in the menu.
  final TextStyle Function(String option) optionStyle;
  final bool overridden;
  final ValueChanged<String> onChanged;
  final VoidCallback onReset;

  const ChatThemeDropdownRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.optionStyle,
    required this.overridden,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                dropdownColor: AppColors.surfaceContainerOf(context),
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                ),
                items: options
                    .map(
                      (o) => DropdownMenuItem(
                        value: o,
                        child: Text(o, style: optionStyle(o)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    onChanged(val);
                  }
                },
              ),
            ),
          ),
          if (overridden)
            IconButton(
              icon: Icon(
                Icons.restart_alt,
                size: 14,
                color: AppColors.porchAmberOf(context),
              ),
              onPressed: onReset,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
