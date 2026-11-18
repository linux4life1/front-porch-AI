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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/settings/widgets/feature_tree.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Waifu-only note. Creates `skills/` on first copy, not during build.
class SkillsFolderNote extends StatefulWidget {
  const SkillsFolderNote({super.key, this.expandDetailsSignal});

  final ExpandSignal? expandDetailsSignal;

  @override
  State<SkillsFolderNote> createState() => _SkillsFolderNoteState();
}

class _SkillsFolderNoteState extends State<SkillsFolderNote> {
  bool _busy = false;
  bool _detailsExpanded = true;

  @override
  void initState() {
    super.initState();
    if (widget.expandDetailsSignal != null) {
      _detailsExpanded = widget.expandDetailsSignal!.expanded;
    }
  }

  @override
  void didUpdateWidget(covariant SkillsFolderNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignal = widget.expandDetailsSignal;
    final prevSignal = oldWidget.expandDetailsSignal;
    if (nextSignal != null && nextSignal.version != prevSignal?.version) {
      _detailsExpanded = nextSignal.expanded;
    }
  }

  Future<void> _chooseFiles() async {
    if (_busy) return;
    final storage = context.read<StorageService>();
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['md'],
      allowMultiple: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    setState(() => _busy = true);
    final paths = [
      for (final file in result.files)
        if (file.path != null && file.path!.isNotEmpty) file.path!,
    ];
    final copied = copySkillSourcesIntoLibrary(storage.skillsDir, paths);
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          copied == 0
              ? 'No SKILL.md folders were copied.'
              : copied == 1
              ? 'Copied 1 skill into skills.'
              : 'Copied $copied skills into skills.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storage = context.watch<StorageService>();
    final skillsPath = storage.rootPath == null
        ? 'skills'
        : '${storage.rootPath}/skills';
    return Padding(
      key: const Key('user-skills-folder-note'),
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _detailsExpanded = !_detailsExpanded),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: AppColors.iconSecondary(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Agent Skills',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'OpenCode SKILL.md folders used by Waifu Coder only.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary(
                            context,
                          ).withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          FeatureDetailsSection(
            expanded: _detailsExpanded,
            body:
                'Waifu Coder also reads OpenCode skill folders here — '
                'one folder per skill, with a SKILL.md inside. Character '
                'chat does not use these. That folder is:\n$skillsPath',
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: FilledButton.icon(
              key: const Key('skills-choose-md'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onAccentOf(context),
              ),
              onPressed: _busy ? null : _chooseFiles,
              icon: const Icon(Icons.file_open, size: 16),
              label: Text(_busy ? 'Copying…' : 'Choose SKILL.md'),
            ),
          ),
        ],
      ),
    );
  }
}
