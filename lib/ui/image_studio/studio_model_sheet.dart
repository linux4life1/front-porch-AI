// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_desk_copy.dart';

/// Change model. Rows are grouped by family. A typed name is kept when
/// the connected app has not listed that file yet.
class StudioModelSheet extends StatefulWidget {
  const StudioModelSheet({
    super.key,
    required this.edit,
    required this.items,
    required this.onPick,
    this.unfit = const {},
  });

  final bool edit;
  final List<String> items;
  final ValueChanged<String> onPick;

  /// Files that look wrong for this model by name. They stay listed, marked,
  /// because a name is only a guess.
  final Set<String> unfit;

  @override
  State<StudioModelSheet> createState() => _StudioModelSheetState();
}

class _StudioModelSheetState extends State<StudioModelSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    // Files whose name looks wrong for this model are listed after all the
    // others, whatever their family, and marked. They are never hidden: a
    // name is only a guess.
    final groups = <ModelFamily, List<String>>{};
    final odd = <ModelFamily, List<String>>{};
    for (final item in widget.items) {
      if (query.isNotEmpty &&
          !item.toLowerCase().contains(query) &&
          !ImageModelFamily.detectFromName(
            item,
          ).label.toLowerCase().contains(query)) {
        continue;
      }
      final family = ImageModelFamily.detectFromName(item);
      final into = widget.unfit.contains(item) ? odd : groups;
      into.putIfAbsent(family, () => []).add(item);
    }
    final typed = _query.trim();
    final offerTyped =
        typed.isNotEmpty &&
        !widget.items.any((item) => item.toLowerCase() == typed.toLowerCase());
    List<ModelFamily> order(Map<ModelFamily, List<String>> from) => [
      for (final family in ModelFamily.values)
        if (from.containsKey(family)) family,
    ];
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        widget.edit ? 'Change model — Edit' : 'Change model — Create',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search families or files',
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (offerTyped)
                    ListTile(
                      title: Text(typed),
                      subtitle: const Text('Use this name'),
                      onTap: () {
                        widget.onPick(typed);
                        Navigator.of(context).pop();
                      },
                    ),
                  ..._section(context, groups, order(groups)),
                  ..._section(context, odd, order(odd), marked: true),
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

  List<Widget> _section(
    BuildContext context,
    Map<ModelFamily, List<String>> groups,
    List<ModelFamily> order, {
    bool marked = false,
  }) {
    return [
      for (final family in order) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            family == ModelFamily.unknown ? 'Other' : family.label,
            style: TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final file in groups[family]!)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Text(
              studioQuantBadge(file),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            title: Text(
              file,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            subtitle: marked
                ? Text(
                    'The name does not look like it fits this model.',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  )
                : null,
            onTap: () {
              widget.onPick(file);
              Navigator.of(context).pop();
            },
          ),
      ],
    ];
  }
}
