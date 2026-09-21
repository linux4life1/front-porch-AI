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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';

/// Chat-speech model chrome: Refresh + searchable picker (not a naked
/// text box with a separate Browse button).
class RemoteModelPickerField extends StatelessWidget {
  const RemoteModelPickerField({
    super.key,
    required this.availableModels,
    required this.selectedId,
    required this.fetching,
    required this.onRefresh,
    required this.onSelected,
    this.onTyped,
    this.dialogTitle = 'Select Model',
  });

  final List<RemoteModelInfo> availableModels;
  final String selectedId;
  final bool fetching;
  final VoidCallback onRefresh;
  final ValueChanged<RemoteModelInfo> onSelected;
  final ValueChanged<String>? onTyped;
  final String dialogTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Model', style: theme.textTheme.bodySmall),
            TextButton.icon(
              onPressed: fetching ? null : onRefresh,
              icon: fetching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(fetching ? 'Loading...' : 'Refresh Models'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (availableModels.isNotEmpty)
          _PickerTrigger(
            selectedId: selectedId,
            availableModels: availableModels,
            onTap: () => showGenericModelSearchDialog<RemoteModelInfo>(
              context,
              availableModels,
              title: dialogTitle,
              getTitle: (m) => m.name,
              getSubtitle: (m) => m.id,
              onSelected: onSelected,
            ),
          )
        else
          TextFormField(
            initialValue: selectedId,
            decoration: InputDecoration(
              hintText: 'e.g. nousresearch/hermes-3-llama-3.1-405b',
              filled: true,
              fillColor: theme.scaffoldBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              suffixIcon: const Icon(Icons.smart_toy, size: 18),
            ),
            onChanged: onTyped == null ? null : (v) => onTyped!(v.trim()),
          ),
      ],
    );
  }
}

class _PickerTrigger extends StatelessWidget {
  const _PickerTrigger({
    required this.selectedId,
    required this.availableModels,
    required this.onTap,
  });

  final String selectedId;
  final List<RemoteModelInfo> availableModels;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final match = availableModels.where((m) => m.id == selectedId);
    return InkWell(
      key: const Key('remote-model-picker'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedId.isNotEmpty
                        ? selectedId
                        : 'Tap to select a model...',
                    style: TextStyle(
                      fontSize: 13,
                      color: selectedId.isNotEmpty
                          ? null
                          : AppColors.textTertiary(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (selectedId.isNotEmpty && match.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      match.first.pricingLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: AppColors.iconSecondary(context),
            ),
          ],
        ),
      ),
    );
  }
}
