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

import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One-row host switcher (KoboldCpp / OpenRouter / Nano-GPT / xAI /
/// LM Studio / oMLX / Custom). oMLX is omitted unless [showOmlx] is true (macOS).
class RemoteProviderBar extends StatelessWidget {
  const RemoteProviderBar({
    super.key,
    required this.selected,
    required this.onSelected,
    this.showOmlx = false,
    this.koboldEnabled = true,
    this.remoteHostsOnly = false,
    this.noneSelected = false,
  });

  final RemoteProviderKind selected;
  final ValueChanged<RemoteProviderKind> onSelected;
  final bool showOmlx;
  final bool koboldEnabled;

  /// OpenRouter / Nano-GPT / xAI / LM Studio only — wizard Setup, not Model Settings.
  final bool remoteHostsOnly;

  /// Worker "Off" — no host pill is highlighted.
  final bool noneSelected;

  static const _all = <(RemoteProviderKind, String)>[
    (RemoteProviderKind.kobold, 'KoboldCpp'),
    (RemoteProviderKind.openRouter, 'OpenRouter'),
    (RemoteProviderKind.nanoGpt, 'Nano-GPT'),
    (RemoteProviderKind.xai, 'xAI'),
    (RemoteProviderKind.lmStudio, 'LM Studio'),
    (RemoteProviderKind.omlx, 'oMLX'),
    (RemoteProviderKind.custom, 'Custom'),
  ];

  static const _remoteHosts = <(RemoteProviderKind, String)>[
    (RemoteProviderKind.openRouter, 'OpenRouter'),
    (RemoteProviderKind.nanoGpt, 'Nano-GPT'),
    (RemoteProviderKind.xai, 'xAI'),
    (RemoteProviderKind.lmStudio, 'LM Studio'),
  ];

  @override
  Widget build(BuildContext context) {
    final source = remoteHostsOnly ? _remoteHosts : _all;
    final items = [
      for (final e in source)
        if (e.$1 != RemoteProviderKind.omlx || showOmlx) e,
    ];
    _Pill pill((RemoteProviderKind, String) e, {bool wrapped = false}) => _Pill(
      label: e.$2,
      selected: !noneSelected && e.$1 == selected,
      enabled: e.$1 != RemoteProviderKind.kobold || koboldEnabled,
      wrapped: wrapped,
      onTap: () => onSelected(e.$1),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow for every name on one line (Model Settings dialog):
        // wrap whole pills onto a second row instead of clipping them.
        if (constraints.maxWidth / items.length < _kMinPillWidth) {
          return Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final e in items) pill(e, wrapped: true)],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(child: pill(items[i])),
            ],
          ],
        );
      },
    );
  }
}

/// Below this per-pill width the row wraps instead of ellipsizing names.
const double _kMinPillWidth = 76;

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.wrapped = false,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Sized to its label (in a [Wrap]) rather than filling a row slot.
  final bool wrapped;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    final bg = !enabled
        ? AppColors.surfaceContainerOf(context).withValues(alpha: 0.5)
        : selected
        ? accent
        : AppColors.surfaceContainerOf(context);
    final fg = !enabled
        ? AppColors.textTertiary(context)
        : selected
        ? AppColors.onChaosAccent
        : AppColors.textSecondary(context);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: wrapped ? null : Alignment.center,
          padding: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: wrapped ? 12 : 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected && enabled ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.1,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
