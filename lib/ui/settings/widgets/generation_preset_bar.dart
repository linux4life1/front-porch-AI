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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

import 'section_header.dart';

/// Settings → Generation's preset bar: load a saved preset, see whether the
/// values still match it, save, link it to the chat model, or go back to
/// the model's recommended values (issue 686).
class GenerationPresetBar extends StatefulWidget {
  const GenerationPresetBar({super.key});

  @override
  State<GenerationPresetBar> createState() => _GenerationPresetBarState();
}

class _GenerationPresetBarState extends State<GenerationPresetBar> {
  bool _busy = false;

  StorageService get _storage => context.read<StorageService>();
  GenPresetActions get _actions => GenPresetActions(_storage);

  /// One write at a time: a second tap before the first lands is dropped.
  Future<void> _run(Future<void> Function() write) async {
    if (_busy) return;
    _busy = true;
    try {
      await write();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the preset: $error')),
        );
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveAsNew() => _run(() async {
    final name = await askGenPresetName(
      context,
      taken: _storage.genPresets.presets.keys,
    );
    if (name != null) await _actions.saveAs(name);
  });

  Future<void> _delete(String name) => _run(() async {
    if (await confirmGenPresetDelete(context, name)) {
      await _actions.delete(name);
    }
  });

  Future<void> _resetAll() => _run(() async {
    final messenger = ScaffoldMessenger.of(context);
    final before = _actions.live;
    final beforeSlot = _storage.genPresets.slot;
    await _actions.resetAll();
    if (before.matchedBy(_actions.live)) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Generation values reset to defaults.'),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _run(() async {
            await before.applyTo(
              _storage.generationSettings,
              _storage.backendSettings,
            );
            await _storage.genPresets.setSlot(beforeSlot);
          }),
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final handles = genPresetsOf(storage);
    if (handles == null) return const SizedBox.shrink();
    final actions = GenPresetActions(storage);
    final presets = handles.presets;
    final model = handles.follower.model;
    final slot = presets.slot;
    final state = actions.state;
    final linked = model.isEmpty ? null : presets.linkedPreset(model.key);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairlineOf(context, 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SectionHeader('Generation preset'),
              GenPresetBadge(
                key: const ValueKey('gen-preset-badge'),
                switch (state) {
                  GenPresetState.notSaved => 'Not saved',
                  GenPresetState.saved => slot!,
                  GenPresetState.edited => '$slot (edited)',
                },
                strong: state != GenPresetState.notSaved,
              ),
              if (linked != null) GenPresetBadge('Linked to ${model.label}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _picker(context, presets, slot)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: slot == null
                    ? 'Load a preset to delete it'
                    : 'Delete “$slot”',
                icon: const Icon(Icons.delete_outline),
                color: AppColors.negativeAccentOf(context),
                onPressed: slot == null ? null : () => _delete(slot),
              ),
            ],
          ),
          if (slot != null && !model.isEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Use this preset whenever ${model.label} is the chat '
                    'model',
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                ),
                Switch(
                  key: const ValueKey('gen-preset-link'),
                  value: linked == slot,
                  activeTrackColor: AppColors.porchAmberOf(context),
                  onChanged: (on) => _run(() => actions.link(on ? slot : null)),
                ),
              ],
            ),
          ],
          _RecommendedLine(
            follower: handles.follower,
            live: actions.live,
            onUse: (values) => _run(
              () => values.applyTo(
                storage.generationSettings,
                storage.backendSettings,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (state == GenPresetState.edited)
                FilledButton(
                  onPressed: () => _run(() => actions.saveAs(slot!)),
                  child: Text('Save to “$slot”'),
                ),
              OutlinedButton(
                onPressed: _saveAsNew,
                child: const Text('Save as new…'),
              ),
              TextButton(
                onPressed: _resetAll,
                child: const Text('Reset all to defaults'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _picker(
    BuildContext context,
    GenPresetSettings presets,
    String? slot,
  ) {
    final names = presets.presets.keys.toList();
    return DropdownButtonFormField<String>(
      // Re-seeded when the slot changes elsewhere (a model switch, the web).
      key: ValueKey('gen-preset-picker-$slot'),
      initialValue: slot,
      isExpanded: true,
      hint: Text(
        names.isEmpty ? 'No saved presets yet' : 'Load a preset...',
        style: const TextStyle(fontSize: 13),
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.cardOf(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      items: [
        for (final name in names)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (name) {
        if (name != null) _run(() => GenPresetActions(_storage).load(name));
      },
    );
  }
}

/// "Recommended for the model: its source" with a button to use those values,
/// while the live ones differ from them.
class _RecommendedLine extends StatelessWidget {
  const _RecommendedLine({
    required this.follower,
    required this.live,
    required this.onUse,
  });

  final GenPresetFollower follower;
  final SamplerValues live;
  final ValueChanged<SamplerValues> onUse;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecommendedSamplers>(
      valueListenable: follower.recommended,
      builder: (context, rec, _) {
        final model = follower.model;
        if (rec.isEmpty || model.isEmpty) return const SizedBox.shrink();
        final matches = rec.values.matchedBy(live);
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recommended for ${model.label}: ${rec.sourceWords}'
                  '${matches ? ', in use' : ''}.',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
              ),
              if (!matches)
                TextButton(
                  onPressed: () => onUse(rec.values),
                  child: const Text('Use recommended'),
                ),
            ],
          ),
        );
      },
    );
  }
}
