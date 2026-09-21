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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Realism-evals `.kcpps` for the managed Kobold process.
class WorkerKoboldKcppsPicker extends StatelessWidget {
  const WorkerKoboldKcppsPicker({
    super.key,
    required this.selectedPath,
    required this.mouthPath,
    required this.modelsMatch,
    required this.presets,
    required this.onChanged,
  });

  final String? selectedPath;
  final String? mouthPath;
  final bool modelsMatch;
  final List<File> presets;
  final ValueChanged<String?> onChanged;

  static const inheritSentinel = '';

  Future<void> _browse() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['kcpps'],
      dialogTitle: 'Select Realism evals .kcpps',
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty) onChanged(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.textTertiary(context);
    final worker = selectedPath?.trim() ?? '';
    final mouth = mouthPath?.trim() ?? '';
    final inherited = worker.isEmpty;
    final paths = <String>{for (final f in presets) p.normalize(f.path)};
    if (worker.isNotEmpty) paths.add(p.normalize(worker));
    if (mouth.isNotEmpty) paths.add(p.normalize(mouth));
    final value = inherited ? inheritSentinel : p.normalize(worker);

    return Column(
      key: const Key('side-jobs-kobold-kcpps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Realism evals .kcpps', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey<String>('side-jobs-kobold-kcpps-$value'),
                initialValue: paths.contains(value) || value == inheritSentinel
                    ? value
                    : inheritSentinel,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: inheritSentinel,
                    child: Text(
                      modelsMatch
                          ? (mouth.isEmpty
                                ? 'Same as chat speech'
                                : 'Same as chat speech (${p.basename(mouth)})')
                          : 'None (model file only)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final path in paths)
                    DropdownMenuItem(
                      value: path,
                      child: Text(
                        p.basename(path),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v == null || v == inheritSentinel) {
                    onChanged(null);
                  } else {
                    onChanged(v);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('side-jobs-kobold-kcpps-browse'),
              onPressed: _browse,
              child: const Text('Browse…'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          modelsMatch && inherited
              ? 'Same GGUF keeps the chat-speech .kcpps. Pick another file '
                    'when Realism evals need their own config.'
              : 'This .kcpps loads with the Realism-evals GGUF on the same '
                    'KoboldCPP. Chat speech keeps its own preset.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
