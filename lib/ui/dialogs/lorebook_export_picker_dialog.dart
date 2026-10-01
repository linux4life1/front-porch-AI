// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Choose which lore entries an Export file write includes. Every entry
// starts ticked. Cancel, or dismissing the dialog, writes nothing.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Entries the user left ticked, in book order. Null means cancel.
Future<List<LorebookEntry>?> showLorebookExportPicker({
  required BuildContext context,
  required List<LorebookEntry> entries,
}) {
  return showDialog<List<LorebookEntry>>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _LorebookExportPickerDialog(entries: entries),
  );
}

class _LorebookExportPickerDialog extends StatefulWidget {
  const _LorebookExportPickerDialog({required this.entries});

  final List<LorebookEntry> entries;

  @override
  State<_LorebookExportPickerDialog> createState() =>
      _LorebookExportPickerDialogState();
}

class _LorebookExportPickerDialogState
    extends State<_LorebookExportPickerDialog> {
  late final Set<int> _checked = {
    for (var i = 0; i < widget.entries.length; i++) i,
  };

  bool get _allSelected => _checked.length == widget.entries.length;

  void _toggle(int index) {
    setState(() {
      if (!_checked.remove(index)) _checked.add(index);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _checked.clear();
      } else {
        _checked
          ..clear()
          ..addAll(List<int>.generate(widget.entries.length, (i) => i));
      }
    });
  }

  void _export() {
    if (_checked.isEmpty) return;
    final indexes = _checked.toList()..sort();
    Navigator.pop(context, [for (final i in indexes) widget.entries[i]]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 480;
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 12 : 28,
        vertical: narrow ? 16 : 40,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: narrow ? size.height - 32 : 640,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Flexible(child: _list(context)),
            _footer(context, narrow),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export lorebook',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tick the entries to write. The rest stay on the card.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: AppColors.textTertiary(context),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      shrinkWrap: true,
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        final keys = entry.keys.isEmpty ? null : entry.keys.join(', ');
        final title = entry.name.trim().isNotEmpty
            ? entry.name.trim()
            : 'Unnamed entry';
        return CheckboxListTile(
          value: _checked.contains(index),
          onChanged: (_) => _toggle(index),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          activeColor: AppColors.formMasterAccent,
          checkColor: AppColors.onChaosAccent,
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: keys == null
              ? null
              : Text(
                  keys,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
        );
      },
    );
  }

  Widget _footer(BuildContext context, bool narrow) {
    final select = TextButton(
      onPressed: _toggleAll,
      child: Text(_allSelected ? 'Select none' : 'Select all'),
    );
    final cancel = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary(context),
      ),
      child: const Text('Cancel'),
    );
    final export = FilledButton(
      onPressed: _checked.isEmpty ? null : _export,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.formMasterAccent,
        foregroundColor: AppColors.onChaosAccent,
        disabledBackgroundColor: AppColors.formMasterAccent.withValues(
          alpha: 0.35,
        ),
        disabledForegroundColor: AppColors.onChaosAccent.withValues(alpha: 0.6),
      ),
      child: const Text('Export'),
    );
    if (narrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [select, export, const SizedBox(height: 4), cancel],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          select,
          const Spacer(),
          cancel,
          const SizedBox(width: 8),
          export,
        ],
      ),
    );
  }
}
