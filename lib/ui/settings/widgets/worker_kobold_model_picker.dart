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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Realism-evals GGUF for the managed Kobold process. Empty = Models-tab file.
class WorkerKoboldModelPicker extends StatelessWidget {
  const WorkerKoboldModelPicker({
    super.key,
    required this.selectedPath,
    required this.mouthPath,
    required this.models,
    required this.onChanged,
  });

  final String? selectedPath;
  final String? mouthPath;
  final List<FileSystemEntity> models;
  final ValueChanged<String?> onChanged;

  static const inheritSentinel = '';

  Future<void> _browse() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      dialogTitle: 'Select Realism evals GGUF',
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
    final paths = <String>{for (final f in models) p.normalize(f.path)};
    if (worker.isNotEmpty) paths.add(p.normalize(worker));
    if (mouth.isNotEmpty) paths.add(p.normalize(mouth));
    final value = inherited ? inheritSentinel : p.normalize(worker);
    final sameAsMouth =
        inherited ||
        (mouth.isNotEmpty &&
            normalizeLocalModelPath(worker) == normalizeLocalModelPath(mouth));

    return Column(
      key: const Key('side-jobs-kobold-model'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Realism evals model', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey<String>('side-jobs-kobold-model-$value'),
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
                      mouth.isEmpty
                          ? 'Same as Models tab'
                          : 'Same as Models tab (${p.basename(mouth)})',
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
              key: const Key('side-jobs-kobold-model-browse'),
              onPressed: _browse,
              child: const Text('Browse…'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          sameAsMouth
              ? 'Evals use the Models-tab file on this KoboldCPP. Pick a '
                    'different GGUF to unload chat speech and load that file '
                    'before Realism checks.'
              : 'Evals unload the chat-speech GGUF and load this file on the '
                    'same KoboldCPP, then stay on it until she talks.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
