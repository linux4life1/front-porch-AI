// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/studio_graph_menu.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

/// Pick a Comfy workflow file. JSON, or a PNG Comfy saved with the
/// workflow stored inside it.
class StudioGraphUpload extends StatefulWidget {
  const StudioGraphUpload({super.key});

  @override
  State<StudioGraphUpload> createState() => _StudioGraphUploadState();
}

class _StudioGraphUploadState extends State<StudioGraphUpload> {
  String _name = '';
  String _json = '';
  String _error = '';
  bool _busy = false;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final picked = await PickerPrefs.pickFiles(
      category: 'studio-graph',
      dialogTitle: 'Workflow file',
      type: FileType.custom,
      allowedExtensions: const ['json', 'png'],
    );
    if (!mounted) return;
    final bytes = await picked?.firstBytes();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      return;
    }
    final json = workflowJsonFromBytes(bytes);
    final name = picked!.files.first.name;
    if (json == null) {
      setState(() {
        _busy = false;
        _name = name;
        _json = '';
        _error = 'That file has no workflow.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _name = name;
      _json = json;
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _json.isEmpty ? 0 : workflowNodeCount(_json);
    return AlertDialog(
      backgroundColor: AppColors.surfaceOf(context),
      title: Text(
        'Upload a workflow',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose a Comfy workflow. That can be the JSON Comfy saves, '
              'or a PNG that still has the workflow stored inside it. '
              'A JPEG does not carry a workflow.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _busy ? null : _pick,
              child: Text(_busy ? 'Reading…' : 'Choose a file'),
            ),
            if (_name.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _name,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_json.isNotEmpty)
                Text(
                  nodes == 1 ? '1 node' : '$nodes nodes',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                  ),
                ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _error,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _json.isEmpty
              ? null
              : () => Navigator.of(context).pop(_json),
          child: const Text('Use this workflow'),
        ),
      ],
    );
  }
}
