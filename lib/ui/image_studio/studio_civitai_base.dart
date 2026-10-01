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
  VoidCallback? onCancel,
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
    preferredSize: Size.fromHeight(
      progress != null && onCancel != null ? 68 : 56,
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (progress != null)
            LinearProgressIndicator(
              value: percent == null ? null : percent / 100,
            ),
          Row(
            children: [
              Expanded(
                child: Text(line, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              if (progress != null && onCancel != null)
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Cancel download'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One searchable base picker. The sheet holds its state: typing into
/// [text] narrows the menu ([query]) without dropping [base], and the field
/// shows [base]'s label once it is left.
class StudioCivitaiBasePicker extends StatelessWidget {
  const StudioCivitaiBasePicker({
    super.key,
    required this.base,
    required this.query,
    required this.text,
    required this.focus,
    required this.installedOnly,
    required this.modelFiles,
    required this.scanning,
    required this.onBase,
    required this.onInstalledOnly,
    this.note,
  });

  final String base;
  final String query;
  final TextEditingController text;
  final FocusNode focus;
  final bool installedOnly;
  final List<String> modelFiles;
  final bool scanning;
  final ValueChanged<String> onBase;
  final ValueChanged<bool> onInstalledOnly;

  /// Why the pick was dropped, when it was.
  final String? note;

  Widget _option(BuildContext context, String api, String label) {
    final picked = api == base;
    return ListTile(
      dense: true,
      selected: picked,
      title: Text(label),
      trailing: picked ? const Icon(Icons.check, size: 18) : null,
      onTap: () => onBase(api),
    );
  }

  Widget _menu(BuildContext context, List<CivitaiBaseGroup> groups) {
    final secondary = AppColors.textSecondary(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _option(context, '', 'Any base'),
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                child: Text(
                  group.title,
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
              for (final choice in group.choices)
                _option(context, choice.api, choice.label),
            ],
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No base matches that.',
                  style: TextStyle(color: secondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final only = installedOnly ? civitaiBasesForFiles(modelFiles) : null;
    final groups = filterCivitaiBaseGroups(
      kCivitaiBaseGroups,
      query: query,
      onlyApis: only,
    );
    final open = focus.hasFocus;
    final secondary = AppColors.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Taps on the menu count as inside the field, so the field keeps
          // focus until a base is picked.
          TextFieldTapRegion(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('studio-civitai-base'),
                  controller: text,
                  focusNode: focus,
                  decoration: InputDecoration(
                    labelText: 'Base model',
                    hintText: 'Type to narrow: Qwen, Flux, SDXL',
                    suffixIcon: open && text.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear),
                            onPressed: text.clear,
                          )
                        : const Icon(Icons.arrow_drop_down),
                  ),
                ),
                if (open) _menu(context, groups),
              ],
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note!, style: TextStyle(color: secondary)),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: installedOnly,
            title: const Text('Only installed models'),
            subtitle: Text(
              scanning
                  ? 'Looking through the models folder…'
                  : 'Limits the bases to ones that match model files on this computer.',
            ),
            onChanged: (next) {
              if (next == null) return;
              onInstalledOnly(next);
            },
          ),
          if (installedOnly && !scanning && query.isEmpty && groups.isEmpty)
            Text(
              'No installed model matches a CivitAI base.',
              style: TextStyle(color: secondary),
            ),
        ],
      ),
    );
  }
}
