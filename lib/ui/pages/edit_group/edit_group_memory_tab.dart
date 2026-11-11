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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/edit_group/memory_rag_model_note.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The group editor's Memory section: how the open chat remembers. A group's
/// memory is the chat's own (its switch, how many memories a turn pulls, how
/// much of the context they may fill, and how much each member's past lines
/// weigh), so it changes the chat as you move it, as it did in Group
/// Settings, and it only exists while a chat is open on the group.
class EditGroupMemoryTab extends StatefulWidget {
  const EditGroupMemoryTab({super.key, required this.chat});

  /// The chat open on the group, or null.
  final ChatService? chat;

  @override
  State<EditGroupMemoryTab> createState() => _EditGroupMemoryTabState();
}

class _EditGroupMemoryTabState extends State<EditGroupMemoryTab> {
  ChatService get _chat => widget.chat!;

  late bool _enabled = widget.chat?.groupRagEnabled ?? true;
  late int _count = widget.chat?.groupRetrievalCount ?? 4;
  late double _budget = widget.chat?.groupMemoryBudgetPercent ?? 10.0;
  late final Map<String, double> _weights = {
    if (widget.chat != null)
      for (final c in widget.chat!.groupCharacters)
        _chat.characterIdFor(c): _chat.ragPriorityForGroupCharacter(c),
  };

  bool _globalOn(BuildContext context) {
    try {
      return Provider.of<StorageService>(
        context,
        listen: false,
      ).memorySettings.ragEnabled;
    } on ProviderNotFoundException {
      return true;
    }
  }

  void _reset() {
    setState(() {
      _enabled = true;
      _count = 4;
      _budget = 10.0;
      _weights.updateAll((_, _) => 1.0);
    });
    _chat
      ..setGroupRAGEnabled(true)
      ..setGroupRetrievalCount(4)
      ..setGroupMemoryBudgetPercent(10.0);
    for (final c in _chat.groupCharacters) {
      _chat.setRAGPriorityForGroupCharacter(c, 1.0);
    }
  }

  Widget _slider({
    required String label,
    required String shown,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final accent = AppColors.emotionAccentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              shown,
              style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: accent,
          inactiveColor: AppColors.borderOf(context),
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chat == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'A group remembers per chat. Open a chat with this group to set '
          'its memory here.',
          key: const ValueKey('edit-group-memory-closed'),
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }
    final globalOn = _globalOn(context);
    final members = _chat.groupCharacters;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Memory · this chat',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              TextButton(
                onPressed: _reset,
                child: const Text('Reset to defaults'),
              ),
            ],
          ),
          Text(
            'Memories come from this group\'s conversation and are searched '
            'when context is dropped. Each character recalls only what they '
            'were there for. These apply to the chat you have open right away.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            tileColor: AppColors.cardOf(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.borderOf(context)),
            ),
            title: const Text('Memory for this group'),
            subtitle: Text(
              globalOn
                  ? 'Also in the chat sidebar, under Memory.'
                  : 'Memory is off in Settings, so no chat uses it. This '
                        "group's choice is kept.",
            ),
            value: _enabled,
            onChanged: globalOn
                ? (v) {
                    setState(() => _enabled = v);
                    _chat.setGroupRAGEnabled(v);
                  }
                : null,
          ),
          if (_enabled && globalOn) const GroupRagModelNote(),
          const SizedBox(height: 8),
          _slider(
            label: 'Memories per turn (retrieval limit)',
            shown: _count == 0 ? 'All' : '$_count',
            value: _count.toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: (v) {
              setState(() => _count = v.round());
              _chat.setGroupRetrievalCount(v.round());
            },
          ),
          _slider(
            label: 'Memory budget (% of context)',
            shown: '${_budget.round()}%',
            value: _budget,
            min: 5,
            max: 25,
            divisions: 20,
            onChanged: (v) {
              setState(() => _budget = v);
              _chat.setGroupMemoryBudgetPercent(v);
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Memory importance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          Text(
            'Boost or suppress how heavily each character\'s past messages '
            'count in what is recalled (0.0 to 2.0; 1.0 is normal).',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
          ),
          for (final CharacterCard c in members)
            _slider(
              label: c.name,
              shown: (_weights[_chat.characterIdFor(c)] ?? 1.0).toStringAsFixed(
                1,
              ),
              value: _weights[_chat.characterIdFor(c)] ?? 1.0,
              min: 0,
              max: 2,
              divisions: 20,
              onChanged: (v) {
                setState(() => _weights[_chat.characterIdFor(c)] = v);
                _chat.setRAGPriorityForGroupCharacter(c, v);
              },
            ),
        ],
      ),
    );
  }
}
