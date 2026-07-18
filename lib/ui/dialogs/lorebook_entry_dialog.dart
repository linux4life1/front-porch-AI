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
import 'package:front_porch_ai/ui/widgets/expanded_editor_dialog.dart';
import 'package:front_porch_ai/ui/widgets/styled_text_controller.dart';
import 'lorebook_entry/lorebook_entry_advanced.dart';
import 'lorebook_entry/lorebook_entry_fields.dart';

/// The ONE lorebook entry editor — used by character editors, the world
/// dialog, group settings, and the chat book. Simple tab = the everyday
/// fields; Advanced = the full SillyTavern grid. Edits happen on a clone,
/// so Cancel discards everything and imported ST metadata always survives
/// a Simple-only edit.
Future<LorebookEntry?> showLorebookEntryDialog({
  required BuildContext context,
  LorebookEntry? existing,
  bool showEnabled = false,
}) {
  return showDialog<LorebookEntry>(
    context: context,
    builder: (_) => _LorebookEntryDialog(
      existing: existing,
      showEnabled: showEnabled,
    ),
  );
}

class _LorebookEntryDialog extends StatefulWidget {
  final LorebookEntry? existing;
  final bool showEnabled;

  const _LorebookEntryDialog({
    this.existing,
    this.showEnabled = false,
  });

  @override
  State<_LorebookEntryDialog> createState() => _LorebookEntryDialogState();
}

class _LorebookEntryDialogState extends State<_LorebookEntryDialog> {
  /// Clone-then-overwrite: the tabs edit this draft in place; Save pops it.
  late final LorebookEntry _draft =
      widget.existing?.clone() ?? LorebookEntry();

  late final TextEditingController _nameCtrl =
      TextEditingController(text: _draft.name);
  late final TextEditingController _keyCtrl =
      TextEditingController(text: _draft.key);
  late final StyledTextController _contentCtrl = StyledTextController(
    text: _draft.content,
    preset: StyledTextPreset.macros,
  );

  int _tab = 0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _keyCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: honey.withValues(alpha: 0.35),
        ),
      ),
      title: Row(
        children: [
          Icon(Icons.menu_book, size: 20, color: honey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.existing == null
                  ? 'Add Lorebook Entry'
                  : 'Edit Lorebook Entry',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          _tabChip('Simple', 0),
          const SizedBox(width: 6),
          _tabChip('Advanced', 1),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildSimpleTab(context),
              LorebookEntryAdvancedTab(draft: _draft),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            _draft.name = _nameCtrl.text.trim();
            _draft.keys = LorebookEntry.parseKeyList(_keyCtrl.text.trim());
            _draft.content = _contentCtrl.text.trim();
            Navigator.pop(context, _draft);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.porchAmberOf(context),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }

  Widget _tabChip(String label, int index) {
    final selected = _tab == index;
    final amber = AppColors.porchAmberOf(context);
    return InkWell(
      onTap: () => setState(() => _tab = index),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? amber.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? amber.withValues(alpha: 0.6)
                : AppColors.borderOf(context).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? amber : AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleTab(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fieldLabel(context, 'Name (optional)'),
        const SizedBox(height: 6),
        AppTextField(
          controller: _nameCtrl,
          decoration: _fieldDecoration(context),
        ),
        const SizedBox(height: 12),
        _fieldLabel(
          context,
          _draft.constant
              ? 'Keywords (Disabled — Always Active)'
              : 'Keywords (comma separated)',
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: _keyCtrl,
          enabled: !_draft.constant,
          decoration: _fieldDecoration(context).copyWith(
            fillColor: _draft.constant
                ? AppColors.surfaceContainerOf(context).withValues(alpha: 0.5)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _fieldLabel(context, 'Content'),
            const Spacer(),
            InkWell(
              onTap: () => showExpandedEditorDialog(
                context: context,
                title: 'Content',
                controller: _contentCtrl,
                hintText: 'Enter lore content...',
              ),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.open_in_full,
                  size: 14,
                  color: AppColors.iconSecondary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: _contentCtrl,
          maxLines: 5,
          decoration: _fieldDecoration(context),
        ),
        const SizedBox(height: 16),
        if (widget.showEnabled) ...[
          _toggleCard(
            context,
            icon: Icons.visibility,
            label: 'Enabled',
            subtitle: 'This entry can be injected when its keys match',
            value: _draft.enabled,
            activeColor: AppColors.porchAmberOf(context),
            onChanged: (v) => setState(() => _draft.enabled = v),
          ),
          const SizedBox(height: 12),
        ],
        _toggleCard(
          context,
          icon: Icons.push_pin,
          label: 'Always Active',
          subtitle: 'Always considered active (ignores trigger keys)',
          value: _draft.constant,
          activeColor: AppColors.porchHoneyOf(context),
          onChanged: (v) => setState(() => _draft.constant = v),
        ),
        if (!_draft.constant) ...[
          const SizedBox(height: 12),
          _sliderBlock(
            context,
            icon: Icons.layers,
            label: 'Sticky Depth',
            help: 'How many turns the entry stays active after triggering',
            valueLabel: '${_draft.stickyDepth}',
            slider: Slider(
              value: _draft.stickyDepth.toDouble().clamp(1, 50),
              min: 1,
              max: 50,
              divisions: 49,
              label: _draft.stickyDepth.toString(),
              onChanged: (v) => setState(() => _draft.stickyDepth = v.round()),
            ),
          ),
          const SizedBox(height: 8),
          _sliderBlock(
            context,
            icon: Icons.casino_outlined,
            label: 'Chance to trigger',
            help: 'Rolled each time the keywords match',
            valueLabel: '${_draft.probability}%',
            slider: Slider(
              value: _draft.probability.toDouble().clamp(0, 100),
              min: 0,
              max: 100,
              divisions: 100,
              label: '${_draft.probability}%',
              onChanged: (v) => setState(() {
                _draft.probability = v.round();
                _draft.useProbability = true;
              }),
            ),
          ),
        ],
        const SizedBox(height: 8),
        LoreFieldRow(
          label: 'Placement',
          subtitle: 'Where this entry lands in the prompt',
          child: LoreDropdown<int>(
            value: _draft.position == 7 ? 0 : _draft.position.clamp(0, 6),
            items: lorePositionLabels,
            onChanged: (v) => setState(() => _draft.position = v),
          ),
        ),
      ],
    );
  }

  Widget _sliderBlock(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String help,
    required String valueLabel,
    required Slider slider,
  }) {
    final honey = AppColors.porchHoneyOf(context);
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                valueLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            help,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: honey,
            inactiveTrackColor:
                AppColors.borderOf(context).withValues(alpha: 0.4),
            thumbColor: honey,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: slider,
        ),
      ],
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context) {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.surfaceContainerOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _toggleCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: value
              ? activeColor.withValues(alpha: 0.3)
              : AppColors.borderOf(context).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      icon,
                      size: 14,
                      color: value
                          ? activeColor
                          : AppColors.iconSecondary(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: activeColor.withValues(alpha: 0.5),
            activeThumbColor: activeColor,
          ),
        ],
      ),
    );
  }
}
