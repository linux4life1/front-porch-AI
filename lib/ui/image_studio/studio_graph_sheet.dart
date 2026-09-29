// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

import 'studio_desk_copy.dart';

/// Change graph. Titles are the names Comfy and Front Porch use. The
/// stored id stays off the row.
class StudioGraphSheet extends StatefulWidget {
  const StudioGraphSheet({
    super.key,
    required this.edit,
    required this.rows,
    this.otherRows = const [],
    required this.note,
    required this.onPick,
    this.onUpload,
    this.onUseOther,
  });

  final bool edit;
  final List<DeskGraphChoice> rows;
  final List<DeskGraphChoice> otherRows;
  final String note;
  final ValueChanged<String> onPick;
  final void Function(
    String json, {
    required bool forEdit,
    required String name,
  })?
  onUpload;
  final void Function(String id, {required bool forEdit})? onUseOther;

  @override
  State<StudioGraphSheet> createState() => _StudioGraphSheetState();
}

class _StudioGraphSheetState extends State<StudioGraphSheet> {
  String _query = '';
  String _error = '';
  String? _pendingJson;
  String _pendingName = '';
  String _pendingStance = '';

  Future<void> _chooseFile() async {
    final picked = await PickerPrefs.pickFiles(
      category: 'studio-graph',
      dialogTitle: 'Workflow file',
      type: FileType.custom,
      allowedExtensions: const ['json', 'png'],
    );
    if (!mounted) return;
    final bytes = await picked?.firstBytes();
    if (!mounted || bytes == null) return;
    final name = picked!.files.first.name;
    final json = workflowJsonFromBytes(bytes);
    if (json == null) {
      final lower = name.toLowerCase();
      final png =
          lower.endsWith('.png') ||
          (bytes.length >= 4 && bytes[0] == 137 && bytes[1] == 80);
      setState(() {
        _error = png ? kStudioPngReject : kStudioFileReject;
        _pendingJson = null;
      });
      return;
    }
    final stance = deskGraphStance(json);
    final current = widget.edit ? 'edit' : 'create';
    if (stance == current) {
      widget.onUpload?.call(json, forEdit: widget.edit, name: name);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = '';
      _pendingJson = json;
      _pendingName = name;
      _pendingStance = stance;
    });
  }

  void _useFile(bool forEdit) {
    final json = _pendingJson;
    if (json == null) return;
    widget.onUpload?.call(json, forEdit: forEdit, name: _pendingName);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final otherShown = query.isEmpty
        ? const <DeskGraphChoice>[]
        : [
            for (final row in widget.otherRows)
              if (row.title.toLowerCase().contains(query) ||
                  row.detail.toLowerCase().contains(query) ||
                  row.id.toLowerCase().contains(query))
                row,
          ];
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
            Text(
              kStudioDropCopy,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            Text(
              kStudioDropKind,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _chooseFile,
                child: const Text('Choose file'),
              ),
            ),
            if (_error.isNotEmpty)
              Text(_error, style: TextStyle(color: AppColors.logError)),
            if (_pendingJson != null && _pendingStance == 'unstated') ...[
              const Text('This graph doesn’t say Create or Edit.'),
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => _useFile(false),
                    child: const Text('Use for Create'),
                  ),
                  TextButton(
                    onPressed: () => _useFile(true),
                    child: const Text('Use for Edit'),
                  ),
                ],
              ),
            ],
            if (_pendingJson != null &&
                _pendingStance != 'unstated' &&
                _pendingStance != (widget.edit ? 'edit' : 'create'))
              TextButton(
                onPressed: () => _useFile(_pendingStance == 'edit'),
                child: Text(
                  _pendingStance == 'edit'
                      ? 'Use it for Edit'
                      : 'Use it for Create',
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty && otherShown.isEmpty
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
                        if (otherShown.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                            child: Text(
                              'Other mode — search found these',
                              style: TextStyle(
                                color: AppColors.formMasterAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          for (final row in otherShown)
                            ListTile(
                              title: Text(row.title),
                              subtitle: Text(row.detail),
                              trailing: TextButton(
                                onPressed: () {
                                  widget.onUseOther?.call(
                                    row.id,
                                    forEdit: !widget.edit,
                                  );
                                  Navigator.of(context).pop();
                                },
                                child: Text(
                                  widget.edit
                                      ? 'Use it for Create'
                                      : 'Use it for Edit',
                                ),
                              ),
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
