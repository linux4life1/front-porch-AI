// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Progress or the download error, pinned under the sheet title.
PreferredSizeWidget? studioCivitaiStatus({
  required String? progressName,
  required String? error,
  required int got,
  required int? total,
}) {
  final progress = progressName;
  if (progress == null && (error == null || error.isEmpty)) return null;
  final percent = total != null && total > 0
      ? ((got / total) * 100).round().clamp(0, 100)
      : null;
  final line = progress == null
      ? error!
      : percent == null
      ? 'Downloading $progress'
      : 'Downloading $progress · $percent%';
  return PreferredSize(
    preferredSize: const Size.fromHeight(56),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress != null)
            LinearProgressIndicator(
              value: percent == null ? null : percent / 100,
            ),
          Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    ),
  );
}

/// Base picker: a text filter, then the bases those words leave.
class StudioCivitaiBasePicker extends StatelessWidget {
  const StudioCivitaiBasePicker({
    super.key,
    required this.base,
    required this.query,
    required this.installedOnly,
    required this.modelFiles,
    required this.scanning,
    required this.onBase,
    required this.onQuery,
    required this.onInstalledOnly,
  });

  final String base;
  final String query;
  final bool installedOnly;
  final List<String> modelFiles;
  final bool scanning;
  final ValueChanged<String> onBase;
  final ValueChanged<String> onQuery;
  final ValueChanged<bool> onInstalledOnly;

  @override
  Widget build(BuildContext context) {
    final only = installedOnly ? civitaiBasesForFiles(modelFiles) : null;
    final groups = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      query: query,
      onlyApis: only,
    );
    final apis = {
      for (final group in groups)
        for (final choice in group.choices) choice.api,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Base model'),
        TextField(
          key: const Key('studio-civitai-base-filter'),
          decoration: const InputDecoration(
            labelText: 'Filter bases',
            hintText: 'Qwen, Flux, SDXL',
          ),
          onChanged: onQuery,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: installedOnly,
          title: const Text('Only installed models'),
          subtitle: Text(
            scanning
                ? 'Looking through the models folder…'
                : 'Limits this list to bases that match model files on this computer.',
          ),
          onChanged: (next) {
            if (next == null) return;
            onInstalledOnly(next);
          },
        ),
        DropdownButton<String>(
          key: const Key('studio-civitai-base'),
          isExpanded: true,
          value: apis.contains(base) ? base : '',
          items: [
            const DropdownMenuItem(value: '', child: Text('Any base')),
            for (final group in groups) ...[
              DropdownMenuItem<String>(
                enabled: false,
                value: 'group:${group.title}',
                child: Text(group.title),
              ),
              for (final choice in group.choices)
                DropdownMenuItem(value: choice.api, child: Text(choice.label)),
            ],
          ],
          onChanged: (next) => onBase(next ?? ''),
        ),
        if (installedOnly && !scanning && groups.isEmpty)
          Text(
            'No installed model matches a CivitAI base.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
      ],
    );
  }
}
