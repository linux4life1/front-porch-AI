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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'gen_preset_access.dart';

/// A model card's "Generation preset" picker: which saved preset loads
/// whenever this model becomes the chat model. "None" unlinks it, and the
/// model then keeps whatever values are in place (or its recommended ones).
class ModelGenPresetPicker extends StatelessWidget {
  const ModelGenPresetPicker({
    super.key,
    this.modelKey,
    this.padding = const EdgeInsets.only(top: 12),
  });

  /// [ChatModelId.key] of the model on the card; null for the current chat
  /// model. An empty key (no model chosen) hides the picker.
  final String? modelKey;
  final EdgeInsets padding;

  static const _none = '';

  Future<void> _link(BuildContext context, String key, String? name) async {
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await GenPresetActions(storage).link(name, modelKey: key);
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not link the preset: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final handles = genPresetsOf(storage);
    if (handles == null) return const SizedBox.shrink();
    final key = modelKey ?? handles.follower.model.key;
    if (key.isEmpty) return const SizedBox.shrink();
    final names = handles.presets.presets.keys.toList();
    final linked = handles.presets.linkedPreset(key) ?? _none;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Generation preset for this model',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            key: ValueKey('model-gen-preset-$key-$linked'),
            initialValue: linked,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.cardOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: _none,
                child: Text(
                  'None (keep current values)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final name in names)
                DropdownMenuItem<String>(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              _link(context, key, name == _none ? null : name);
            },
          ),
          const SizedBox(height: 4),
          Text(
            names.isEmpty
                ? 'Save a preset in Settings → Generation to link it here.'
                : 'Loaded whenever this model is the chat model.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
