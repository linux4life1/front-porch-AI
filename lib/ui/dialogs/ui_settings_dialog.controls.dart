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

part of 'ui_settings_dialog.dart';

/// Appearance controls (avatar-lock toggle, generic slider) and the Chat
/// Colors row (its "Select Color" picker is the shared [showColorPicker]) for
/// [UiSettingsDialog].
/// Extracted verbatim from UiSettingsDialog; direct state access preserves
/// behavior.
extension _UiSettingsControlsSection on _UiSettingsDialogState {
  // ── Appearance controls ──────────────────────────────────────────────────

  Widget _buildAvatarLockedToggle(BuildContext context) {
    final character = _characterNotifier.value!;
    final locked = character.frontPorchExtensions?.avatarLocked ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock Avatar Size',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              Text(
                'Avatar won\'t grow past default size when sidebar is wider',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: locked,
          onChanged: (val) async {
            _updateAvatarLocked(context, val);
          },
          activeTrackColor: AppColors.formMasterAccent,
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: AppColors.formMasterAccent,
          inactiveColor: AppColors.borderOf(context),
        ),
      ],
    );
  }

  Widget _buildColorRow(
    BuildContext context,
    String label,
    Color color,
    void Function(Color) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.borderOf(context), width: 1),
            ),
            child: IconButton(
              icon: Icon(Icons.color_lens, size: 20, color: swatchInkOn(color)),
              onPressed: () => showColorPicker(context, color, onChanged),
            ),
          ),
        ],
      ),
    );
  }
}
