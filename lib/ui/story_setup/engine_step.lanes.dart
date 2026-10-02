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

part of 'engine_step.dart';

/// The "who does which job" pickers and the switch rows of [EngineStep].
extension _EngineStepLanes on EngineStep {
  Widget _laneField(
    BuildContext context,
    String job,
    StoryModelLane value,
    ({String main, String? worker}) labels,
    ValueChanged<StoryModelLane> onPick,
  ) {
    final hasWorker = labels.worker != null;
    final effective = hasWorker ? value : StoryModelLane.main;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          job,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.backgroundOf(context),
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<StoryModelLane>(
              value: effective,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
              items: [
                DropdownMenuItem(
                  value: StoryModelLane.main,
                  child: Text(labels.main, overflow: TextOverflow.ellipsis),
                ),
                if (hasWorker)
                  DropdownMenuItem(
                    value: StoryModelLane.worker,
                    child: Text(
                      labels.worker!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: hasWorker
                  ? (v) {
                      if (v != null) {
                        onPick(v);
                        onChanged();
                      }
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required String title,
    String? trailing,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.porchAmberOf(context),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
      ],
    ),
  );
}
