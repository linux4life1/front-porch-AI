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

import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/services/gen_presets/gen_presets.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/gen_presets/gen_presets.dart';

/// The sampler values one chat holds itself; null fields follow the global
/// ones.
SamplerValues chatOwnSamplers(ChatGenerationSettings c) => SamplerValues(
  temperature: c.temperature,
  minP: c.minP,
  topP: c.topP,
  topK: c.topK,
  repeatPenalty: c.repeatPenalty,
  repeatPenaltyTokens: c.repeatPenaltyTokens,
  xtcThreshold: c.xtcThreshold,
  xtcProbability: c.xtcProbability,
  dryMultiplier: c.dryMultiplier,
  dynamicTempEnabled: c.dynamicTempEnabled,
  dynamicTempRange: c.dynamicTempRange,
  maxLength: c.maxLength,
  reasoningEnabled: c.reasoningEnabled,
  reasoningEffort: c.reasoningEffort,
  stopSequences: c.stopSequences,
);

/// Chat Settings' "Preset for this chat": follow the model (the global
/// values, which its linked preset or recommended values set), or copy a
/// saved preset into this chat's own values. The same row serves a 1:1 and
/// a group chat; both keep their values in the session's settings.
class ChatGenPresetRow extends StatefulWidget {
  const ChatGenPresetRow({
    super.key,
    required this.gen,
    required this.storage,
    required this.onLoaded,
  });

  final ChatGenerationSettings gen;
  final StorageService storage;

  /// The chat's new settings, for the dialog to keep and save.
  final ValueChanged<ChatGenerationSettings> onLoaded;

  @override
  State<ChatGenPresetRow> createState() => _ChatGenPresetRowState();
}

class _ChatGenPresetRowState extends State<ChatGenPresetRow> {
  static const _follow = '';
  bool _busy = false;

  void _pick(GenPresetHandles handles, String? name) {
    if (name == null) return;
    final values = name == _follow ? null : handles.presets.presets[name];
    widget.onLoaded(
      GenPresetActions.loadIntoChat(
        widget.gen,
        values,
        values == null ? null : name,
      ),
    );
  }

  Future<void> _saveAsPreset(GenPresetHandles handles) async {
    if (_busy) return;
    _busy = true;
    try {
      final name = await askGenPresetName(
        context,
        taken: handles.presets.presets.keys,
        title: 'Save this chat’s values as a preset',
      );
      if (name == null) return;
      final values = chatOwnSamplers(
        widget.gen,
      ).over(GenPresetActions(widget.storage).live);
      await handles.presets.savePreset(name, values);
      widget.onLoaded(GenPresetActions.loadIntoChat(widget.gen, values, name));
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

  @override
  Widget build(BuildContext context) {
    final handles = genPresetsOf(widget.storage);
    if (handles == null) return const SizedBox.shrink();
    final presets = handles.presets.presets;
    final own = chatOwnSamplers(widget.gen);
    final loaded = presets.containsKey(widget.gen.genPresetName)
        ? widget.gen.genPresetName
        : null;
    final model = handles.follower.model;
    final linked = model.isEmpty
        ? null
        : handles.presets.linkedPreset(model.key);
    final badge = switch (loaded) {
      final name? =>
        presets[name]!.matchedBy(
              own.over(GenPresetActions(widget.storage).live),
            )
            ? name
            : '$name (edited)',
      null => own.isEmpty ? 'Following the model' : 'This chat’s own values',
    };
    final accent = AppColors.formAccentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Preset for this chat',
              style: TextStyle(fontWeight: FontWeight.bold, color: accent),
            ),
            GenPresetBadge(
              badge,
              key: const ValueKey('chat-gen-preset-badge'),
              strong: loaded != null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('chat-gen-preset-${loaded ?? _follow}'),
          initialValue: loaded ?? _follow,
          isExpanded: true,
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
            DropdownMenuItem<String>(
              value: _follow,
              child: Text(
                linked == null
                    ? 'Follow the model'
                    : 'Follow the model: “$linked”',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final name in presets.keys)
              DropdownMenuItem<String>(
                value: name,
                child: Text(name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (name) => _pick(handles, name),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a preset to keep it in this chat whatever the model. '
          'Changes below are this chat’s own and sit on top.',
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary(context),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _saveAsPreset(handles),
            child: const Text('Save this chat’s values as a preset…'),
          ),
        ),
      ],
    );
  }
}
