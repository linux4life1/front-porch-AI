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

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Small shared warm-porch field widgets for the lorebook entry editor tabs.

/// Uppercase section header with a honey accent, matching the sidebar's
/// sub-header language.
class LoreSectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const LoreSectionHeader({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.porchHoneyOf(context)),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled row hosting any control on its trailing side.
class LoreFieldRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final Widget child;
  const LoreFieldRow({
    super.key,
    required this.label,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          child,
        ],
      ),
    );
  }
}

/// Compact integer field writing through [onChanged]. Empty text maps to
/// [emptyValue] (used for "0 = off" and nullable overrides).
class LoreIntField extends StatefulWidget {
  final int? value;
  final int? emptyValue;
  final ValueChanged<int?> onChanged;
  final double width;
  const LoreIntField({
    super.key,
    required this.value,
    required this.onChanged,
    this.emptyValue,
    this.width = 64,
  });

  @override
  State<LoreIntField> createState() => _LoreIntFieldState();
}

class _LoreIntFieldState extends State<LoreIntField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.textPrimary(context)),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceContainerOf(context),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (text) =>
            widget.onChanged(int.tryParse(text.trim()) ?? widget.emptyValue),
      ),
    );
  }
}

/// Tri-state dropdown for nullable booleans: null = "Use global".
class LoreTriState extends StatelessWidget {
  final bool? value;
  final ValueChanged<bool?> onChanged;
  const LoreTriState({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LoreDropdown<String>(
      value: value == null ? 'global' : (value! ? 'on' : 'off'),
      items: const {'global': 'Use global', 'on': 'On', 'off': 'Off'},
      onChanged: (v) => onChanged(v == 'global' ? null : v == 'on'),
    );
  }
}

/// Compact dense dropdown in the warm field style.
class LoreDropdown<T> extends StatelessWidget {
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const LoreDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary(context)),
        dropdownColor: AppColors.surfaceOf(context),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Small warm toggle row (label + switch) — the compact sibling of the
/// Simple tab's toggle cards.
class LoreToggle extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const LoreToggle({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LoreFieldRow(
      label: label,
      subtitle: subtitle,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor:
            AppColors.porchAmberOf(context).withValues(alpha: 0.5),
        activeThumbColor: AppColors.porchAmberOf(context),
      ),
    );
  }
}
