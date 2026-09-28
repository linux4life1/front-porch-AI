// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Change graph. Titles are the names Comfy and Front Porch use. The
/// stored id stays off the row.
class StudioGraphSheet extends StatefulWidget {
  const StudioGraphSheet({
    super.key,
    required this.edit,
    required this.rows,
    required this.note,
    required this.onPick,
  });

  final bool edit;
  final List<DeskGraphChoice> rows;
  final String note;
  final ValueChanged<String> onPick;

  @override
  State<StudioGraphSheet> createState() => _StudioGraphSheetState();
}

class _StudioGraphSheetState extends State<StudioGraphSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final row in widget.rows)
        if (query.isEmpty ||
            row.title.toLowerCase().contains(query) ||
            row.detail.toLowerCase().contains(query) ||
            row.id.toLowerCase().contains(query))
          row,
    ];
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        widget.edit ? 'Change graph — Edit' : 'Change graph — Create',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.note,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search graphs',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Text(
                      'No graph matches that.',
                      style: TextStyle(color: AppColors.textSecondary(context)),
                    )
                  : ListView(
                      children: [
                        for (var i = 0; i < shown.length; i++) ...[
                          if (i == 0 || shown[i].group != shown[i - 1].group)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(
                                shown[i].group,
                                style: TextStyle(
                                  color: AppColors.formMasterAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            title: Text(
                              shown[i].title,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              shown[i].detail,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                            enabled: shown[i].group != 'Could not read',
                            onTap: shown[i].group == 'Could not read'
                                ? null
                                : () {
                                    widget.onPick(shown[i].id);
                                    Navigator.of(context).pop();
                                  },
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
