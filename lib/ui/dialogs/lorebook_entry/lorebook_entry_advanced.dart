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

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'lorebook_entry_fields.dart';

/// Position values shared by the Advanced tab and the Simple tab's
/// placement preset (numeric = the ST position stored on the entry).
const Map<int, String> lorePositionLabels = {
  0: 'With character info',
  1: 'After character info',
  2: "Author's Note — top",
  3: "Author's Note — bottom",
  4: 'In recent chat (@depth)',
  5: 'Example dialogues — top',
  6: 'Example dialogues — bottom',
};

/// Advanced tab: the full SillyTavern field grid, editing the live [draft]
/// entry in place (the dialog cloned it on open, so Cancel discards
/// everything and Save pops the draft — imported metadata always survives).
/// Kept alive via IndexedStack in the dialog so its controllers persist
/// across tab switches.
class LorebookEntryAdvancedTab extends StatefulWidget {
  final LorebookEntry draft;
  const LorebookEntryAdvancedTab({super.key, required this.draft});

  @override
  State<LorebookEntryAdvancedTab> createState() =>
      _LorebookEntryAdvancedTabState();
}

class _LorebookEntryAdvancedTabState extends State<LorebookEntryAdvancedTab> {
  LorebookEntry get d => widget.draft;

  late final TextEditingController _secondaryCtrl =
      TextEditingController(text: d.secondaryKeys.join(', '));
  late final TextEditingController _groupCtrl =
      TextEditingController(text: d.group);

  @override
  void dispose() {
    _secondaryCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  void _set(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LoreSectionHeader(icon: Icons.rule, label: 'Conditions'),
        AppTextField(
          controller: _secondaryCtrl,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            hintText: 'Secondary keywords (comma separated)',
            hintStyle:
                TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (text) =>
              d.secondaryKeys = LorebookEntry.parseKeyList(text),
        ),
        LoreFieldRow(
          label: 'Secondary logic',
          subtitle: 'How secondary keywords gate the trigger',
          child: LoreDropdown<int>(
            value: d.selectiveLogic.clamp(0, 3),
            items: const {
              SelectiveLogic.andAny: 'AND any of them',
              SelectiveLogic.notAll: 'NOT all of them',
              SelectiveLogic.notAny: 'NOT any of them',
              SelectiveLogic.andAll: 'AND all of them',
            },
            onChanged: (v) => _set(() => d.selectiveLogic = v),
          ),
        ),
        LoreToggle(
          label: 'Keywords are regex patterns',
          subtitle: 'Treat every keyword as a regular expression',
          value: d.useRegex,
          onChanged: (v) => _set(() => d.useRegex = v),
        ),

        const LoreSectionHeader(icon: Icons.place, label: 'Placement & priority'),
        LoreFieldRow(
          label: 'Position',
          child: LoreDropdown<int>(
            value: d.position == 7 ? 0 : d.position.clamp(0, 6),
            items: lorePositionLabels,
            onChanged: (v) => _set(() => d.position = v),
          ),
        ),
        if (d.position == 4) ...[
          LoreFieldRow(
            label: 'Depth',
            subtitle: 'Messages up from the end of the chat',
            child: LoreIntField(
              value: d.depth,
              emptyValue: 4,
              onChanged: (v) => d.depth = (v ?? 4).clamp(0, 999),
            ),
          ),
          LoreFieldRow(
            label: 'Speak as',
            child: LoreDropdown<int>(
              value: (d.role ?? 0).clamp(0, 2),
              items: const {0: 'System', 1: 'User', 2: 'Assistant'},
              onChanged: (v) => _set(() => d.role = v),
            ),
          ),
        ],
        LoreFieldRow(
          label: 'Order',
          subtitle: 'Higher = closer to the reply, survives budget cuts',
          child: LoreIntField(
            value: d.order,
            emptyValue: 100,
            onChanged: (v) => d.order = v ?? 100,
          ),
        ),
        LoreToggle(
          label: 'Ignore token budget',
          subtitle: 'Always inject, even when lore is over budget',
          value: d.ignoreBudget,
          onChanged: (v) => _set(() => d.ignoreBudget = v),
        ),

        const LoreSectionHeader(icon: Icons.timer_outlined, label: 'Timing (messages)'),
        LoreFieldRow(
          label: 'Sticky',
          subtitle: 'Stays force-active this many messages',
          child: LoreIntField(
            value: d.sticky == 0 ? null : d.sticky,
            emptyValue: 0,
            onChanged: (v) => d.sticky = (v ?? 0).clamp(0, 9999),
          ),
        ),
        LoreFieldRow(
          label: 'Cooldown',
          subtitle: 'Cannot re-trigger for this many messages',
          child: LoreIntField(
            value: d.cooldown == 0 ? null : d.cooldown,
            emptyValue: 0,
            onChanged: (v) => d.cooldown = (v ?? 0).clamp(0, 9999),
          ),
        ),
        LoreFieldRow(
          label: 'Delay',
          subtitle: 'Silent until the chat reaches this length',
          child: LoreIntField(
            value: d.delay == 0 ? null : d.delay,
            emptyValue: 0,
            onChanged: (v) => d.delay = (v ?? 0).clamp(0, 9999),
          ),
        ),

        const LoreSectionHeader(icon: Icons.autorenew, label: 'Chain reactions'),
        LoreToggle(
          label: 'Can be triggered by other lore',
          value: !d.excludeRecursion,
          onChanged: (v) => _set(() => d.excludeRecursion = !v),
        ),
        LoreToggle(
          label: 'Can trigger other lore',
          value: !d.preventRecursion,
          onChanged: (v) => _set(() => d.preventRecursion = !v),
        ),
        LoreFieldRow(
          label: 'Only via chaining, level',
          subtitle: '0 = off; N = activates on chain sweep N+',
          child: LoreIntField(
            value: d.delayUntilRecursion == 0 ? null : d.delayUntilRecursion,
            emptyValue: 0,
            onChanged: (v) => d.delayUntilRecursion = (v ?? 0).clamp(0, 10),
          ),
        ),

        const LoreSectionHeader(icon: Icons.manage_search, label: 'Matching overrides'),
        LoreFieldRow(
          label: 'Scan depth',
          subtitle: 'Messages this entry watches (empty = global)',
          child: LoreIntField(
            value: d.scanDepth,
            onChanged: (v) => d.scanDepth = v,
          ),
        ),
        LoreFieldRow(
          label: 'Case sensitive',
          child: LoreTriState(
            value: d.caseSensitive,
            onChanged: (v) => _set(() => d.caseSensitive = v),
          ),
        ),
        LoreFieldRow(
          label: 'Whole words',
          child: LoreTriState(
            value: d.matchWholeWords,
            onChanged: (v) => _set(() => d.matchWholeWords = v),
          ),
        ),

        const LoreSectionHeader(icon: Icons.shuffle, label: 'Variety group'),
        AppTextField(
          controller: _groupCtrl,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            hintText: 'Group name(s), comma separated — one member fires at a time',
            hintStyle:
                TextStyle(fontSize: 12, color: AppColors.textTertiary(context)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (text) => d.group = text.trim(),
        ),
        LoreFieldRow(
          label: 'Weight',
          subtitle: 'Random-pick weight within the group',
          child: LoreIntField(
            value: d.groupWeight,
            emptyValue: 100,
            onChanged: (v) => d.groupWeight = (v ?? 100).clamp(1, 10000),
          ),
        ),
        LoreToggle(
          label: 'Prioritize in group',
          subtitle: 'Wins the group by Order instead of randomly',
          value: d.groupOverride,
          onChanged: (v) => _set(() => d.groupOverride = v),
        ),
        LoreFieldRow(
          label: 'Score by matched keys',
          child: LoreTriState(
            value: d.useGroupScoring,
            onChanged: (v) => _set(() => d.useGroupScoring = v),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
