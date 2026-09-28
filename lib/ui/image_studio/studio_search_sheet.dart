// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Searchable list. The desk uses one sheet for models, graphs, and LoRAs.
class StudioSearchSheet extends StatefulWidget {
  const StudioSearchSheet({
    super.key,
    required this.title,
    required this.items,
    required this.onPick,
  });

  final String title;
  final List<String> items;
  final ValueChanged<String> onPick;

  @override
  State<StudioSearchSheet> createState() => _StudioSearchSheetState();
}

class _StudioSearchSheetState extends State<StudioSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final item in widget.items)
        if (query.isEmpty || item.toLowerCase().contains(query)) item,
    ];
    final typed = _query.trim();
    final offerTyped =
        typed.isNotEmpty &&
        !widget.items.any((item) => item.toLowerCase() == typed.toLowerCase());
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        widget.title,
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (offerTyped)
                    ListTile(
                      title: Text('Use $typed'),
                      onTap: () {
                        widget.onPick(typed);
                        Navigator.of(context).pop();
                      },
                    ),
                  for (final item in shown)
                    ListTile(
                      title: Text(item),
                      onTap: () {
                        widget.onPick(item);
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
