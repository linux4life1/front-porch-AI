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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class DeskWizardSitDownStep extends StatelessWidget {
  const DeskWizardSitDownStep({
    super.key,
    required this.folderPath,
    required this.coworker,
    required this.backendLabel,
    required this.isLocalBackend,
    required this.toolsSupported,
    required this.mode,
    required this.honestyAccepted,
    required this.onModeChanged,
    required this.onHonestyChanged,
    required this.onConfirm,
  });

  final String folderPath;
  final CharacterCard? coworker;
  final String backendLabel;
  final bool isLocalBackend;
  final bool toolsSupported;
  final DeskMode mode;
  final bool honestyAccepted;
  final ValueChanged<DeskMode> onModeChanged;
  final ValueChanged<bool> onHonestyChanged;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    final can = deskCanSitDown(
      honestyAccepted: honestyAccepted,
      toolsSupported: toolsSupported,
      hasFolder: folderPath.isNotEmpty,
      hasCoworker: coworker != null,
    );
    final honey = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text(
            'Sit down',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  amber.withValues(alpha: 0.28),
                  honey.withValues(alpha: 0.12),
                  AppColors.cardOf(context),
                ],
              ),
              border: Border.all(color: amber.withValues(alpha: 0.55)),
              boxShadow: [
                BoxShadow(color: amber.withValues(alpha: 0.22), blurRadius: 16),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Folder: $folderPath',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
                Text(
                  'Coworker: ${coworker?.name ?? '—'}',
                  style: TextStyle(color: honey, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Backend: ${backendLabel.isEmpty ? 'current Settings backend' : backendLabel}',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Starting mode',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final m in DeskMode.values)
                ChoiceChip(
                  label: Text(m.name[0].toUpperCase() + m.name.substring(1)),
                  selected: mode == m,
                  onSelected: (_) => onModeChanged(m),
                  selectedColor: amber.withValues(alpha: 0.3),
                ),
            ],
          ),
          if (mode == DeskMode.yolo) ...[
            const SizedBox(height: 8),
            Text(
              kDeskYoloWarning,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
          if (isLocalBackend) ...[
            const SizedBox(height: 12),
            Text(
              kDeskLocalModelWarning,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
          if (!toolsSupported) ...[
            const SizedBox(height: 12),
            Text(
              kDeskToolsUnsupported,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            kDeskHonestyBody,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const Key('desk-honesty-checkbox'),
            value: honestyAccepted,
            onChanged: (v) => onHonestyChanged(v ?? false),
            title: const Text(kDeskHonestyCheckbox),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('desk-sit-down-confirm'),
              onPressed: can ? onConfirm : null,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Sit down'),
              style: ElevatedButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: AppColors.onChaosAccent,
                disabledBackgroundColor: AppColors.surfaceContainerOf(context),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
